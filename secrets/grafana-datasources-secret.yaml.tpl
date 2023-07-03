apiVersion: 1
datasources:
- name: InfluxDB
  type: influxdb
  access: proxy
  database: home
  user: 'grafana'
  url: http://influxdb.influxdb.svc:8086
  jsonData:
    timeInterval: "10s"
  secureJsonData:
    password: xxx
