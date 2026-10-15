# CPU-only personal MoonRobo workspace; no physical bridge or robot SDK.
# Render into deploy/local/ with envsubst; never commit the rendered cluster file.
# Prerequisites: a WebIDE gateway service account, trusted CA ConfigMap,
# pinned images, a workspace storage class and a Traefik websecure entrypoint.
apiVersion: v1
kind: ConfigMap
metadata:
  name: moonrobo-webide-runtime
  namespace: ${NAMESPACE}
data:
  host.json: |
    {
      "namespace_name": "${NAMESPACE}",
      "controller_namespace": "${CONTROLLER_NAMESPACE}",
      "model_gateway_namespace": "${MOONGATE_NAMESPACE}",
      "comfyui_image": "${COMFY_IMAGE}",
      "model_proxy_image": "${MODEL_PROXY_IMAGE}",
      "storage_class": "${STORAGE_CLASS}",
      "storage_access_mode": "${STORAGE_ACCESS_MODE}",
      "storage_gib": 20,
      "cpu_millis": 1000,
      "memory_mib": 4096,
      "controller_origin": "${CONTROLLER_ORIGIN}",
      "model_gateway_origin": "${MOONGATE_ORIGIN}",
      "public_api_base_url": "${PUBLIC_ORIGIN}/user/v1",
      "trusted_ca_config_map": "${TRUST_CONFIG_MAP}",
      "controller_port": ${CONTROLLER_PORT},
      "model_gateway_port": ${MOONGATE_PORT},
      "kubernetes_origin": "https://kubernetes.default.svc",
      "kubernetes_ca_file": "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
      "kubernetes_token_file": "/var/run/secrets/kubernetes.io/serviceaccount/token"
    }
  container.json: |
    {
      "image": "${MOONROBO_IMAGE}",
      "command": ["/usr/local/bin/moonrobo"],
      "args": ["serve", "/workspace", "/opt/moonrobo/ui", "0.0.0.0", "5290", "127.0.0.1", "5391"],
      "port": 5290,
      "cpu_millis": 2000,
      "memory_mib": 4096,
      "gpu": false
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: moonrobo-webide-gateway
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels: {app: moonrobo-webide-gateway}
  template:
    metadata:
      labels: {app: moonrobo-webide-gateway}
    spec:
      serviceAccountName: ${WEBIDE_SERVICE_ACCOUNT}
      nodeSelector:
        ${WORKSPACE_NODE_LABEL_KEY}: "${WORKSPACE_NODE_LABEL_VALUE}"
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: gateway
          image: ${WEBIDE_GATEWAY_IMAGE}
          imagePullPolicy: IfNotPresent
          ports: [{name: http, containerPort: 8082}]
          env:
            - {name: LUNANEXA_WEBIDE_BIND, value: "0.0.0.0:8082"}
            - {name: LUNANEXA_WEBIDE_CLIENT_ID, value: moonrobo}
            - {name: LUNANEXA_WEBIDE_CONFIG_FILE, value: /config/host.json}
            - {name: LUNANEXA_WEBIDE_CONTAINER_FILE, value: /config/container.json}
            - {name: LUNANEXA_WEBIDE_REQUIRE_EXCLUSIVE, value: "false"}
            - {name: LUNANEXA_WEBIDE_PUBLIC_ORIGIN, value: "${PUBLIC_ORIGIN}"}
            - {name: LUNANEXA_WEBIDE_PUBLIC_BASE_PATH, value: /moonrobo}
            - {name: SSL_CERT_FILE, value: /run/platform-trust/ca-bundle.crt}
          volumeMounts:
            - {name: runtime, mountPath: /config, readOnly: true}
            - {name: trust, mountPath: /run/platform-trust, readOnly: true}
          readinessProbe:
            tcpSocket: {port: 8082}
            periodSeconds: 5
          resources:
            requests: {cpu: 100m, memory: 128Mi}
            limits: {cpu: 1000m, memory: 1024Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
      volumes:
        - name: runtime
          configMap: {name: moonrobo-webide-runtime}
        - name: trust
          configMap: {name: "${TRUST_CONFIG_MAP}"}
---
apiVersion: v1
kind: Service
metadata:
  name: moonrobo-webide-gateway
  namespace: ${NAMESPACE}
spec:
  selector: {app: moonrobo-webide-gateway}
  ports: [{name: http, port: 8082, targetPort: 8082}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: moonrobo-webide-public-ingress
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels: {app: moonrobo-webide-gateway}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${INGRESS_NAMESPACE}
          podSelector:
            matchLabels:
              ${INGRESS_POD_LABEL_KEY}: ${INGRESS_POD_LABEL_VALUE}
      ports: [{protocol: TCP, port: 8082}]
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: moonrobo-strip-prefix
  namespace: ${NAMESPACE}
spec:
  stripPrefix: {prefixes: [/moonrobo]}
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: moonrobo-public
  namespace: ${NAMESPACE}
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`${PUBLIC_HOST}`) && PathPrefix(`/moonrobo/`)
      kind: Rule
      middlewares: [{name: moonrobo-strip-prefix}]
      services: [{name: moonrobo-webide-gateway, port: 8082}]
  tls:
    secretName: ${PUBLIC_TLS_SECRET}
