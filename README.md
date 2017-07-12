# Metrics comparisons for ManageIQ

## Query requirements

MetricStore should

*  downsample 15 minute granularity data to 1 hour buckets
*  upsample 15 minute granularity data to 5 minute buckets with interpolated data
*  aggregate vm data to a host
*  graph the max of cpu usage of all vms
*  graph the number of vms running on a host
