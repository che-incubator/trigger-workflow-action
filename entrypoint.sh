#!/bin/bash

dieWith() 
{
	echo "$*" >&2
	exit 1
}

validateArgs() {
    # TODO add any more validation?
    if [[ -z ${INPUT_WORKFLOW_ID} ]] && [[ -z ${INPUT_WORKFLOW_NAME} ]]; then
        dieWith "[ERROR] either workflow ID or name must be specified"
    fi
}

# for a given GH repo and action name, compute workflow_id
# warning: variable workflow_id is a global, so don't call this in parallel executions!
computeWorkflowId() {
    this_repo=$1
    this_action_name=$2
    workflow_id=$(curl -sSL https://api.github.com/repos/${this_repo}/actions/workflows -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" | jq --arg search_field "${this_action_name}" '.workflows[] | select(.name == $search_field).id'); # echo "workflow_id = $workflow_id"
    if [[ ! $workflow_id ]]; then
        die_with "[ERROR] Could not compute workflow id from https://api.github.com/repos/${this_repo}/actions/workflows - check your GITHUB_TOKEN is active"
    fi
    # echo "[INFO] Got workflow_id $workflow_id for $this_repo action '$this_action_name'"
}


# generic method to call a GH action and pass in a single var=val parameter 
invokeAction() {
    # if provided, use previously computed workflow_id; otherwise compute it from the action's name so we can invoke the GH action by id
    if [[ $INPUT_WORKFLOW_ID ]]; then
        workflow_id=$INPUT_WORKFLOW_ID
    else
        computeWorkflowId $INPUT_REPO "$INPUT_WORKFLOW_NAME"
        # now we have a global value for $workflow_id
    fi
    if [[ ${INPUT_REPO} == "che-incubator"* ]]; then
        this_github_token=${CHE_INCUBATOR_BOT_GITHUB_TOKEN}
    else
        this_github_token=${GITHUB_TOKEN}
    fi

    if [[ -z $INPUT_PARAMETERS ]]; then
        this_parameters="{}"
    else
        this_parameters="${INPUT_PARAMETERS}"
    fi

    curl -sSL https://api.github.com/repos/${INPUT_REPO}/actions/workflows/${workflow_id}/dispatches -X POST -H "Authorization: token ${this_github_token}" -H "Accept: application/vnd.github.v3+json" -d "{\"ref\":\"master\",\"inputs\": ${this_parameters} }" || dieWith "[ERROR] Problem invoking action https://github.com/${INPUT_REPO}/actions?query=workflow%3A%22${this_action_name// /+}%22"
    echo "[INFO] Invoked '${INPUT_WORKFLOW_NAME}' action ($workflow_id) - see https://github.com/${INPUT_REPO}/actions?query=workflow%3A%22${INPUT_WORKFLOW_NAME// /+}%22"
}

waitAction() {
    # initial delay
    sleep ${INPUT_WAIT_INITIAL_DELAY} * 60

    workflow_run_id=$(curl -X GET "https://api.github.com/repos/${INPUT_REPO}/actions/workflows/${workflow_id}/runs" \
    -H 'Accept: application/vnd.github.antiope-preview+json' \
    -H "Authorization: Bearer $INPUT_GITHUB_TOKEN" | jq '[.workflow_runs[]] | first')

    while [[ ${conclusion} == "null" && ${status} != "\"completed\"" ]]
    do
        sleep ${INPUT_WAIT_INTERVAL}
        echo "[INFO] querying workflow status and conclusion"
        workflow_run=$(curl -X GET "https://api.github.com/repos/${INPUT_REPO}/actions/workflows/${workflow_id}/runs" \
        -H 'Accept: application/vnd.github.antiope-preview+json' \
        -H "Authorization: Bearer $INPUT_GITHUB_TOKEN" | jq '.workflow_runs[] | select(.id == '$workflow_run_id')')
        conclusion=$(echo $workflow_run | jq '.conclusion')
        status=$(echo $workflow_run | jq '.status')

        echo "Conclusion: ${conclusion}"
        echo "Status ${status}"
    done

  if [[ ${conclusion} == "\"success\"" && ${status} == "\"completed\"" ]]
  then
    echo "[INFO] Workflow has completed successfully "
  else
    echo "[WARN] Workflow did not finish successfully: ${conclusion}"
  fi
}


validateArgs
invokeAction 
waitAction