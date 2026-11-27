# Songshop's storage key. Copy to songshop-gcs.env and fill in the values.
# Make a key with:
#   gcloud storage hmac create songshop-storage@leetcloud-173303.iam.gserviceaccount.com --project leetcloud-173303
#
# The other Songshop secret, songshop-deploy-key, is an SSH private key with no
# template: generate it with ssh-keygen and add the public half to the songshop
# repo as a read-only deploy key.
GCS_HMAC_ACCESS_ID=xxx
GCS_HMAC_SECRET=xxx
