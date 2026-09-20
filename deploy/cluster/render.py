#!/usr/bin/env python3
"""Render every per-node artefact for the cluster layout from cluster.json.

The point of rendering rather than hand-writing: the node list, the fabric
pairing, the inventory and the runtime configuration all come from one file,
so a node cannot be half-declared in four places.

Writes into --output:
  node-agent-<id>.yaml        the Deployment to apply
  inventory-<id>.json         the node's inventory ConfigMap payload
  kubernetes-runtime-<id>.json the node's runtime adapter configuration
  fabric-<id>.yaml            netplan file declaring its private-fabric address
  rbac.yaml                   runtime namespace + Role/RoleBinding
Nothing here talks to a cluster: applying is one-click.sh's job.
"""
import argparse
import json
import os
import pathlib
import re
import sys

PLACEHOLDER = re.compile(r"\$\{([A-Z_]+)\}")


def load(path):
    with open(path) as handle:
        return json.load(handle)


def render(template_text, values):
    missing = []

    def replace(match):
        name = match.group(1)
        if name not in values:
            missing.append(name)
            return match.group(0)
        return str(values[name])

    rendered = PLACEHOLDER.sub(replace, template_text)
    if missing:
        raise SystemExit(f"template placeholders without a value: {sorted(set(missing))}")
    return rendered


def require(node, key):
    if key not in node:
        raise SystemExit(f"node {node.get('id', '?')} is missing '{key}'")
    return node[key]


def check_pairing(nodes):
    """A fabric address is a promise that the peer exists and names back."""
    by_id = {require(node, "id"): node for node in nodes}
    for node in nodes:
        peer = node.get("fabricPeer")
        address = node.get("fabricAddress")
        if not peer and not address:
            continue
        if not peer or not address:
            raise SystemExit(
                f"node {node['id']}: fabricPeer and fabricAddress must be set together"
            )
        if peer not in by_id:
            raise SystemExit(f"node {node['id']} names an unknown peer {peer}")
        if by_id[peer].get("fabricPeer") != node["id"]:
            raise SystemExit(
                f"CX7 pairing is one-way: {node['id']} names {peer}, "
                f"but {peer} names {by_id[peer].get('fabricPeer')!r}"
            )
    paired = [node["id"] for node in nodes if node.get("fabricPeer")]
    if len(paired) % 2 != 0:
        raise SystemExit(f"fabric declarations do not pair up: {paired}")


def inventory(node, cluster):
    return {
        "node_id": node["id"],
        "agent_version": node.get("agentVersion", "0.2.0-20260918-arm64"),
        "os_release": node.get("osRelease", "Ubuntu 24.04.5 LTS"),
        "runtime_names": node.get("runtimeNames", []),
        "accelerators": [
            {
                "device_id": require(node, "gpuUuid"),
                "architecture": node.get("architecture", "nvidia-sm121"),
                "memory_total_mib": node.get("memoryTotalMib", 124608),
                "memory_free_mib": node.get("memoryTotalMib", 124608),
                "healthy": True,
            }
        ],
        "labels": {
            "lunanexa.data-classes": ",".join(node.get("dataClasses", ["Confidential"])),
            "lunanexa.gpu.model": node.get("gpuModel", "NVIDIA GB10"),
            "lunanexa.gpu.driver": node.get("gpuDriver", "580.178.04"),
            "lunanexa.gpu.compute-capability": node.get("computeCapability", "12.1"),
            **({"lunanexa.io/cx7-peer": node["fabricPeer"]} if node.get("fabricPeer") else {}),
            **({"lunanexa.io/cx7-address": node["fabricAddress"]} if node.get("fabricAddress") else {}),
        },
        "taints": [],
    }


def runtime_config(node, cluster, control_addresses):
    runtime = cluster["runtime"]
    config = {
        "namespace_name": runtime["namespace"],
        "node_name": node["id"],
        "node_id": node["id"],
        "model_cache_root": runtime["modelCacheRoot"],
        "runtime_port": runtime["runtimePort"],
        "run_as_user": runtime["runAsUser"],
        "device_class_name": runtime["deviceClassName"],
        "controller_addresses": control_addresses,
        "runtime_secrets": [],
        **({"fabric_address": node["fabricAddress"]} if node.get("fabricAddress") else {}),
    }
    # How this cluster hands a pod its GPUs, and how a runtime recognises its
    # controller, are cluster facts rather than per-node ones.
    if runtime.get("devicePluginResource"):
        config["device_plugin_resource"] = runtime["devicePluginResource"]
    if runtime.get("runtimeClassName"):
        config["runtime_class_name"] = runtime["runtimeClassName"]
    if runtime.get("controllerNamespace"):
        config["controller_namespace"] = runtime["controllerNamespace"]
    return config


def registries_yaml(cluster):
    """The k3s registry config: the pull-through mirrors this cluster uses, plus
    the private registry this platform publishes to. Written whole rather than
    appended to, because appending a second top-level `configs:` key to an
    existing file produces YAML that no longer parses."""
    registry = cluster.get("registry")
    if not registry:
        return None
    lines = ["mirrors:"]
    for name, endpoint in (registry.get("mirrors") or {}).items():
        lines.append(f'  "{name}":')
        lines.append("    endpoint:")
        lines.append(f'      - "{endpoint}"')
    authority = f'{registry["host"]}:{registry["port"]}'
    lines.append("configs:")
    lines.append(f'  "{authority}":')
    lines.append("    tls:")
    lines.append(f'      ca_file: "{registry["caFile"]}"')
    return "\n".join(lines) + "\n"


def fabric_plan(node):
    """The netplan file that makes the fabric address survive a reboot.

    `optional: true` matters: the link is point to point, and boot must not
    wait for it.
    """
    return {
        "network": {
            "version": 2,
            "ethernets": {
                node["fabricInterface"]: {
                    "addresses": [f"{node['fabricAddress']}/24"],
                    "optional": True,
                }
            },
        }
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--template-dir", required=True)
    parser.add_argument("--control-address", action="append", default=[],
                        help="controller address for a controller outside the cluster; omitted when the runtime config names a controller namespace")
    parser.add_argument("--node", action="append", default=[])
    parser.add_argument("--without-fabric", action="store_true")
    arguments = parser.parse_args()

    cluster = load(arguments.manifest)
    # The declaration as a whole is what has to be coherent: a single-node run
    # still validates the pairs it is not rendering.
    check_pairing(cluster["nodes"])
    nodes = cluster["nodes"]
    if arguments.node:
        wanted = set(arguments.node)
        unknown = wanted - {node["id"] for node in nodes}
        if unknown:
            raise SystemExit(f"--node names nodes not in the manifest: {sorted(unknown)}")
        nodes = [node for node in nodes if node["id"] in wanted]

    namespace = cluster["namespace"]
    runtime = cluster["runtime"]
    images = cluster["images"]
    control_addresses = arguments.control_address
    output = pathlib.Path(arguments.output)
    output.mkdir(parents=True, exist_ok=True)

    template = (pathlib.Path(arguments.template_dir) / "node-agent.yaml.tmpl").read_text()
    for node in nodes:
        node_id = node["id"]
        node_values = {
            "NAMESPACE": namespace,
            "NODE_ID": node_id,
            "NODE_IMAGE": images["node"],
            "SECRET_NAME": f"lunanexa-node-agent-material-{node_id}",
            "INVENTORY_CM": f"lunanexa-node-inventory-{node_id}",
            "RUNTIME_CM": f"lunanexa-node-runtime-{node_id}",
            "MODEL_CACHE_ROOT": runtime["modelCacheRoot"],
            "RUNTIME_CONFIG_PATH": runtime["configPath"],
            "RUNTIME_STATE_PATH": runtime["statePath"],
        }
        (output / f"node-agent-{node_id}.yaml").write_text(render(template, node_values))
        (output / f"inventory-{node_id}.json").write_text(
            json.dumps(inventory(node, cluster), indent=2) + "\n"
        )
        (output / f"kubernetes-runtime-{node_id}.json").write_text(
            json.dumps(runtime_config(node, cluster, control_addresses), indent=2) + "\n"
        )
        registries = registries_yaml(cluster)
        if registries is not None:
            (output / f"registries-{node_id}.yaml").write_text(registries)
        if node.get("fabricInterface"):
            (output / f"fabric-{node_id}.yaml").write_text(
                json.dumps(fabric_plan(node), indent=2) + "\n"
            )
        elif node.get("fabricAddress") and not arguments.without_fabric:
            print(
                f"warning: {node_id} declares a fabric address but no fabricInterface,"
                " so no netplan file was rendered and the address will not survive a reboot",
                file=sys.stderr,
            )

    if cluster.get("registry"):
        registry = cluster["registry"]
        summary = {
            "authority": f'{registry["host"]}:{registry["port"]}',
            "clusterIP": registry.get("clusterIP", ""),
            "caFile": registry["caFile"],
            "publish": registry.get("publish", []),
        }
        (output / "registry.json").write_text(json.dumps(summary, indent=2) + "\n")

    rbac = (pathlib.Path(arguments.template_dir) / ".." / "node-kubernetes-rbac.yaml").resolve()
    (output / "rbac.yaml").write_text(
        render(
            rbac.read_text(),
            {"NAMESPACE": namespace, "RUNTIME_NAMESPACE": runtime["namespace"]},
        )
    )
    print(f"rendered {len(nodes)} node(s) into {output}")


if __name__ == "__main__":
    main()
