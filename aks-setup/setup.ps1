# # Variable Declaration
[CmdletBinding()]
param(
     [Parameter(Mandatory)]
     [string]$ClusterName,
     [Parameter(Mandatory)]
     [string]$RegistryName
)

# $RegistryName="ServianLdAcr"
$ClusterName="istioaks"
$ResourceGroup="MohanRam"
$Namespace='ingress-controller'
$SourceRegistry="registry.k8s.io"
$ControllerImage="ingress-nginx/controller"
$ControllerTag="v1.2.1"
$PatchImage="ingress-nginx/kube-webhook-certgen"
$PatchTag="v1.1.1"
$DefaultBackendImage="defaultbackend-amd64"
$DefaultBackendTag="1.5"
$IngressDns="$ClusterName".ToLower()


az login --use-device-code

az aks get-credentials --name $ClusterName -g $ResourceGroup

# az acr import `
#   --name $RegistryName `
#   --source $SourceRegistry `
#   --image "${ControllerImage}:${ControllerTag}"

# az acr import \
#   --name $RegistryName \
#   --source $SourceRegistry \
#   --image "${PatchImage}:${PatchTag}"

# az acr import \
# --name $RegistryName \
# --source $SourceRegistry \
# --image "${DefaultBackendImage}:${DefaultBackendTag}"

# Add the ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Set variable for ACR location to use for pulling images
# $AcrUrl = $(az acr show -n $RegistryName --query loginServer -o tsv)

# Use Helm to deploy an NGINX ingress controller
helm install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-controller `
    --create-namespace `
    --set controller.replicaCount=2 `
    --set controller.nodeSelector."kubernetes\.io/os"=linux `
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

Start-Sleep -s 60

$nginxExtIp=$(kubectl -n $Namespace get svc ingress-nginx-controller -o json | jq -r .status.loadBalancer.ingress[].ip)
$pip=$(az network public-ip list -g "MC_MohanRam_${IngressDns}_centralindia" --query "[?ipAddress!=null]|[?contains(ipAddress, '$nginxExtIp')].[id]" --output tsv)

# Update public ip address with DNS name
az network public-ip update --ids $pip --dns-name $IngressDns
# Display the FQDN
$fqdn = $(az network public-ip show --ids $pip --query "[dnsSettings.fqdn]" --output tsv)

# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io

# Update your local Helm chart repository cache
helm repo update

helm install cert-manager jetstack/cert-manager `
    --namespace ingress-controller `
    --set installCRDs=true `
    --set nodeSelector."kubernetes\.io/os"=linux `
    --set webhook.nodeSelector."kubernetes\.io/os"=linux `
    --set cainjector.nodeSelector."kubernetes\.io/os"=linux

Start-Sleep -s 60


$original_file = "./aks-setup/cluster-issuer.yaml"
$destination_file =  "./aks-setup/cluster-issuer-withdata.yaml"
(Get-Content $original_file) | Foreach-Object {
    $_ -replace '@@@IngressDns', $fqdn  `
       -replace '@@@Namespace', $Namespace
    } | Set-Content $destination_file

#creates cluster issuer and certificate
kubectl apply -f "./aks-setup/cluster-issuer-withdata.yaml" --namespace $Namespace
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

kubectl create ns api
# kubectl create ns prometheus

# helm install prometheus prometheus-community/kube-prometheus-stack -n prometheus

kubectl apply -f "$PSScriptroot/deployment.yml"