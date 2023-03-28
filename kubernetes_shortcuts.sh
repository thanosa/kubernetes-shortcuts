set_env() { 
    if [[ $1 != "stg" && $1 != "dev" ]]; then
        echo "invalid environment: ${1}";
        return
    fi
    environment=$1
    export KUBECONFIG="$K8/kubeconfig-${environment}"
}

get_env() {
    if [[ -z $KUBECONFIG ]]; then
        echo "Nothing set"
    fi
    echo "$(basename $KUBECONFIG | cut -d\- -f2)"
}

check_tags() {
    OLD_ENV=$(get_env)
    
        for environment in "stg" "dev"; do
            set_env $environment
            echo "env: $environment"
            kubectl -n $ns get pods -o jsonpath="{.items[*].spec.containers[*].image}"  | tr -s '[[:space:]]' '\n' | sort | uniq -c | grep $service_name
            echo ""
        done

    set_env $OLD_ENV
}

build() {
    ans=$L/services/$service_dir/api/devops/ansible
    if [[ ! -d $ans ]]; then echo "ansible dir not found: $ans"; fi

    yml=$ans/$playbook
    if [[ ! -f $yml ]]; then echo "playbook not found: $yml"; fi

    sed -i "s/.*${prop}.*/    ${prop}: \"${image_tag}\"/" $yml && grep $prop $yml
    
    echo "Service:   $service_name"
    echo "Tag:       $image_tag"
    echo ""
    echo "Ready to build ?" && read

    cd $ans
    ansible-playbook $playbook -i inventory.ini --tags $ansible_tag 
    cd -
}

deploy() {
    deployments=$(kubectl -n $ns get pods  | grep $service_name | awk '{print $1}' | rev | cut -d- -f3- | rev)
    
    echo "env:   $(basename $KUBECONFIG)"
    echo "tag:   $image_tag"
    echo ""
    echo "deployments: "
    for d in $deployments; do
        echo "  $d"
    done
    echo ""
    echo "Ready to DEPLOY?" && read

    for deployment in $deployments; do
        kubectl -n $ns set image deployment/$deployment $service_name=$image_prefix:$image_tag
        echo ""
    done
}

patch() {

    deployments=$(kubectl -n $ns get pods  | grep $service_name | awk '{print $1}' | rev | cut -d- -f3- | rev | sort -u)
    
    echo "env:   $(basename $KUBECONFIG)"
    echo "tag:   $image_tag"
    echo ""
    echo "deployments: "
    for d in $deployments; do
        echo "  $d"
    done
    echo ""
    echo "Ready to PATCH ?" && read

    for deployment in $deployments; do
        kubectl -n $ns patch deployment $deployment -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": {  \"redeploy\": \"${USER}$(date +%s)\"}}}}}"
        echo ""
    done
}

deploy_all() {
    for e in "dev" "stg"; do
        set_env $e
        deploy
    done
}

patch_all() {
    for e in "dev" "stg"; do
        set_env $e
        patch
    done
}

monitor() {
    watch -n.2 "kubectl -n $ns get pods | grep $service_name"
}

list_pods() {
    get_env
    kubectl -n $ns get pods | grep $service_name
}

set_pod() {
    export pod=$(kubectl -n $ns get pods  | grep $service_name | tail -1 | awk '{print $1}') 
    echo $pod
}

log_pod() {
    if [[ -z $pod ]]; then
        echo "no pod set"
        return
    fi
    kubectl -n $ns logs $pod -f 
}

describe_pod() {
    if [[ -z $pod ]]; then
        echo "no pod set"
        return
    fi
    kubectl -n $ns describe pod $pod 
}

exec_pod() {
    if [[ -z $pod ]]; then
        echo "no pod set"
        return
    fi
    echo ""
    echo "cat /mnt/envvars/api.env"
    echo "cat /mnt/secrets/jwt-public-key"
    echo ""
    kubectl -n $ns exec $pod -it -- /bin/bash 
}


. ./functions.sh

ns="namespace"
service_name="that"
service_dir="that_dir"
ansible_tag="build_that_service_api_docker_image"
playbook="that-service-api-local.yml"
prop="that_service_api_docker_image_tag"
image_prefix="storage.azurecr.io/datalake/datalake-service-api"

image_tag="v1.0.1"


set_env "dev"
# set_env "stg"