// Emit a standalone static landing deployment. Environment-specific inputs stay outside source.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import crypto from 'node:crypto';
const root=path.dirname(fileURLToPath(import.meta.url));
const [host,node,image,tlsSecret]=process.argv.slice(2);
if(!/^[a-z0-9.-]+$/.test(host||'')||!node||!image?.includes('@sha256:')||!tlsSecret)throw Error('Usage: node render-deployment.mjs HOST MANAGEMENT_NODE DIGEST_PINNED_NGINX_IMAGE TLS_SECRET');
const ns='lunanexa',name='nexai-public-landing',labels={app:name};
const data={'index.html':fs.readFileSync(path.join(root,'index.html'),'utf8'),'site.css':fs.readFileSync(path.join(root,'site.css'),'utf8'),'nginx.conf':fs.readFileSync(path.join(root,'nginx.conf'),'utf8')};
if(data['index.html'].includes('__PUBLIC_TRIAL_KEY__')||data['index.html'].includes('__PUBLIC_TRIAL_QR__'))throw Error('This public-key edition requires approved deployment inputs; use release-public-test-key.mbtx instead of publishing placeholders.');
if(fs.existsSync(path.join(root,'site.js')))data['site.js']=fs.readFileSync(path.join(root,'site.js'),'utf8');
const binaryData=Object.fromEntries(fs.readdirSync(path.join(root,'assets')).map(f=>[f,fs.readFileSync(path.join(root,'assets',f)).toString('base64')]));
const hash=crypto.createHash('sha256').update(JSON.stringify({data,binaryData})).digest('hex').slice(0,12);
const contentName=`${name}-${hash}`;
const metadata=n=>({name:n,namespace:ns,labels});
const resources=[
 {apiVersion:'v1',kind:'ConfigMap',metadata:metadata(contentName),immutable:true,data,binaryData},
 {apiVersion:'apps/v1',kind:'Deployment',metadata:metadata(name),spec:{replicas:1,revisionHistoryLimit:3,selector:{matchLabels:labels},template:{metadata:{labels,annotations:{'nexai.io/content-sha':hash}},spec:{automountServiceAccountToken:false,nodeSelector:{'kubernetes.io/hostname':node},securityContext:{runAsNonRoot:true,runAsUser:101,runAsGroup:101,seccompProfile:{type:'RuntimeDefault'}},containers:[{name:'web',image,imagePullPolicy:'IfNotPresent',command:['nginx','-c','/site/nginx.conf','-g','daemon off;'],ports:[{name:'http',containerPort:8080}],resources:{requests:{cpu:'25m',memory:'32Mi'},limits:{cpu:'200m',memory:'128Mi'}},securityContext:{allowPrivilegeEscalation:false,readOnlyRootFilesystem:true,capabilities:{drop:['ALL']}},readinessProbe:{httpGet:{path:'/health',port:'http'},initialDelaySeconds:1,periodSeconds:3},livenessProbe:{httpGet:{path:'/health',port:'http'},initialDelaySeconds:10,periodSeconds:20},volumeMounts:[{name:'site',mountPath:'/site',readOnly:true},{name:'tmp',mountPath:'/tmp'}]}],volumes:[{name:'site',configMap:{name:contentName}},{name:'tmp',emptyDir:{}}]}}}},
 {apiVersion:'v1',kind:'Service',metadata:metadata(name),spec:{selector:labels,ports:[{name:'http',port:8080,targetPort:'http'}]}},
 {apiVersion:'networking.k8s.io/v1',kind:'NetworkPolicy',metadata:metadata(name),spec:{podSelector:{matchLabels:labels},policyTypes:['Ingress','Egress'],ingress:[{from:[{namespaceSelector:{matchLabels:{'kubernetes.io/metadata.name':'kube-system'}},podSelector:{matchLabels:{'app.kubernetes.io/name':'traefik'}}}],ports:[{protocol:'TCP',port:8080}]}],egress:[]}},
 {apiVersion:'traefik.io/v1alpha1',kind:'IngressRoute',metadata:metadata(name),spec:{entryPoints:['websecure'],routes:[{match:`Host(\`${host}\`) && (Path(\`/\`) || Path(\`/index.html\`) || PathPrefix(\`/community-assets/\`) || PathPrefix(\`/nexai-assets/\`))`,kind:'Rule',priority:30,services:[{name,port:8080}]}],tls:{secretName:tlsSecret}}},
 {apiVersion:'traefik.io/v1alpha1',kind:'Middleware',metadata:metadata(`${name}-https`),spec:{redirectScheme:{scheme:'https',permanent:true}}},
 {apiVersion:'traefik.io/v1alpha1',kind:'IngressRoute',metadata:metadata(`${name}-http`),spec:{entryPoints:['web'],routes:[{match:`Host(\`${host}\`) && Path(\`/\`)`,kind:'Rule',priority:30,middlewares:[{name:`${name}-https`}],services:[{name,port:8080}]}]}}
];
process.stdout.write(JSON.stringify({apiVersion:'v1',kind:'List',items:resources}));
