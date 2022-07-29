notifiers:
  - name: gotham_galactic
    type: slack
    org_id: 1
    uid: gotham_galactic
    is_default: true
    send_reminder: true
    frequency: 1h
    disable_resolve_message: false
    # See `Supported Settings` section for settings supporter for each
    # alert notification type.
    settings:
      recipient: 'XXX'
      token: 'xoxb'
      uploadImage: true
      url: https://slack.com