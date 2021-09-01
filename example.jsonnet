local kp =
  (import 'kube-prometheus/kube-prometheus.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-eks.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-all-namespaces.libsonnet') +
  // Uncomment the following imports to enable its patches
  // (import 'kube-prometheus/kube-prometheus-anti-affinity.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-managed-cluster.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-node-ports.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-static-etcd.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-thanos-sidecar.libsonnet') +
   (import 'kube-prometheus/kube-prometheus-custom-metrics.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-external-metrics.libsonnet') +
  {
    _config+:: {
      namespace: 'monitoring',
      prometheus+:: {
        namespaces: [],
      },
      alertmanager+: {
        config: importstr 'alertmanager-config.yaml',
      },
    },

    prometheus+:: {
      gameserver: {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'ServiceMonitor',
        metadata: {
          name: 'servicemonitor-custom',
          namespace: 'monitoring',
          labels: {
             'k8s-app': "gameserver",
          }
        },
        spec: {
          jobLabel: 'k8s-app',
          endpoints: [
            {
              targetPort: 8080,
              path: "/metric",
              interval: "30s",    // 每30s抓取一次信息
              bearerTokenFile: "/var/run/secrets/kubernetes.io/serviceaccount/token",
            },
          ],
          selector: {
            matchLabels: {},
          },
          namespaceSelector: {
              matchNames: ['dev'],
          },
        },
      },
      prometheus+: {
        spec+: {  // https://github.com/coreos/prometheus-operator/blob/master/Documentation/api.md#prometheusspec
          // If a value isn't specified for 'retention', then by default the '--storage.tsdb.retention=24h' arg will be passed to prometheus by prometheus-operator.
          // The possible values for a prometheus <duration> are:
          //  * https://github.com/prometheus/common/blob/c7de230/model/time.go#L178 specifies "^([0-9]+)(y|w|d|h|m|s|ms)$" (years weeks days hours minutes seconds milliseconds)
          retention: '30d',
          // Reference info: https://github.com/coreos/prometheus-operator/blob/master/Documentation/user-guides/storage.md
          // By default (if the following 'storage.volumeClaimTemplate' isn't created), prometheus will be created with an EmptyDir for the 'prometheus-k8s-db' volume (for the prom tsdb).
          // This 'storage.volumeClaimTemplate' causes the following to be automatically created (via dynamic provisioning) for each prometheus pod:
          //  * PersistentVolumeClaim (and a corresponding PersistentVolume)
          //  * the actual volume (per the StorageClassName specified below)
          storage: {  // https://github.com/coreos/prometheus-operator/blob/master/Documentation/api.md#storagespec
            volumeClaimTemplate: {  // https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.11/#persistentvolumeclaim-v1-core (defines variable named 'spec' of type 'PersistentVolumeClaimSpec')
              apiVersion: 'v1',
              kind: 'PersistentVolumeClaim',
              spec: {
                accessModes: ['ReadWriteOnce'],
                // https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.11/#resourcerequirements-v1-core (defines 'requests'),
                // and https://kubernetes.io/docs/concepts/policy/resource-quotas/#storage-resource-quota (defines 'requests.storage')
                resources: { requests: { storage: '100Gi' } },
                // A StorageClass of the following name (which can be seen via `kubectl get storageclass` from a node in the given K8s cluster) must exist prior to kube-prometheus being deployed.
                storageClassName: 'gp2',
                // The following 'selector' is only needed if you're using manual storage provisioning (https://github.com/coreos/prometheus-operator/blob/master/Documentation/user-guides/storage.md#manual-storage-provisioning).
                // And note that this is not supported/allowed by AWS - uncommenting the following 'selector' line (when deploying kube-prometheus to a K8s cluster in AWS) will cause the pvc to be stuck in the Pending status and have the following error:
                //  * 'Failed to provision volume with StorageClass "ssd": claim.Spec.Selector is not supported for dynamic provisioning on AWS'
                // selector: { matchLabels: {} },
              },
            },
          },  // storage
        },  // spec
      },  // prometheus
    },  // prometheus

    grafanaDashboards+:: {  //  monitoring-mixin compatibility
      'request-dashboard.json': (import 'mytry-grafana-dashboard.json'),
    },
    grafana+:: {
      dashboards+:: {  // use this method to import your dashboards to Grafana
        'request-dashboard.json': (import 'mytry-grafana-dashboard.json'),
      },
    },
    prometheusAlerts+:: {
      groups+: [
        {
          name: 'pod-restart.rules',
          rules: [
            {
              alert: 'PodRestart',
              expr: 'rate(kube_pod_container_status_restarts_total[5m]) > 0',
              labels: {
                severity: 'warning',
              },
              annotations: {
                description: 'pod restart event detected.',
              },
            },
          ],
        },
        {
          name: 'node-increase.rules',
          rules: [
            {
              alert: 'NodeIncrease',
              expr: '(sum(kube_node_info) - sum(kube_node_info offset 5m)) > 0',
              labels: {
                severity: 'warning',
              },
              annotations: {
                description: 'node number increased event detected.',
              },
            },
          ],
        },
        // 测试环境可以把这个rule去掉，因为测试环境pod更新比较频繁，总有新pod产生。会频繁误触发这条报警
        {
          name: 'pod-increase.rules',
          rules: [
            {
              alert: 'PodIncrease',
              expr: '(sum(kube_pod_info) by (created_by_name)) - (sum(kube_pod_info offset 5m)  by (created_by_name)) > 0',
              labels: {
                severity: 'warning',
              },
              annotations: {
                description: 'pod number increased event detected.',
              },
            },
          ],
        },
      ],
    },
  };

{ ['setup/0namespace-' + name]: kp.kubePrometheus[name] for name in std.objectFields(kp.kubePrometheus) } +
{
  ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
  for name in std.filter((function(name) name != 'serviceMonitor'), std.objectFields(kp.prometheusOperator))
} +
// serviceMonitor is separated so that it can be created after the CRDs are ready
{ 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
{ ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) } +
{ ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) }
