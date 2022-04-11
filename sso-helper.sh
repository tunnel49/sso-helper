#!/usr/bin/env -S bash -euo pipefail -O extglob

profile=${1}

sso_role_name=$(aws configure get ${profile}.sso_role_name)
sso_account_id=$(aws configure get ${profile}.sso_account_id)
sso_start_url=$(aws configure get ${profile}.sso_start_url)
sso_region=$(aws configure get ${profile}.sso_region)

region=$(aws configure get ${profile}.region)

get_token () {
  local credential=$(jq -s 'map(select(
      .startUrl == "'$sso_start_url'" and
      .region == "'$sso_region'"
      ))' ~/.aws/sso/cache/*)
  case $(jq '. | length' <<< $credential) in
    0) 
      return 1
      ;;
    1) 
      expire=$(date -d $(jq -r '.[0].expiresAt' <<< $credential) +%s)
      now=$(date +%s)
      if (( $expire > ($now + 5) ))
      then
        jq -r '.[0].accessToken' <<< $credential
        return 0
      else
        return 2
      fi
      ;;
    *) 
      >&2 echo expected at most a single match 
      return 3
      ;;
  esac 
}

mk_config () {
  local token rc=0
  token=$(get_token) || rc=$?
  case $rc in
    0) 
      :
      ;;
    1)
      >&2 echo "[mk_config] SSO credential not found in cache, try to log in"
      >&2 echo "aws sso login --profile ${profile}"
      exit 1
      ;;
    2)
      >&2 echo "[mk_config] SSO token has expired, log in and try again"
      >&2 echo "aws sso login --profile ${profile}"
      exit 2
      ;;
    3) 
      >&2 echo "[mk_config] multiple SSO tokens found, check your .aws/sso/cache"
      exit 3
      ;;
    *)
      >&2 echo "[mk_config] get_token returned unexpected error"
      exit 4
      ;;
  esac
  credential=$(aws sso get-role-credentials \
    --profile ${profile} \
    --role-name ${sso_role_name} \
    --account-id ${sso_account_id} \
    --access-token ${token} )
  aws configure set "profile.${profile}.aws_access_key_id" \
    "$(jq -r '.roleCredentials.accessKeyId' <<< $credential)"
  aws configure set "profile.${profile}.aws_secret_access_key" \
    "$(jq -r '.roleCredentials.secretAccessKey' <<< $credential)"

  >&2 echo "Profile updated: $profile"
  }

mk_config
