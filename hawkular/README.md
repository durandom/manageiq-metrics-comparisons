# Hawkular metrics as a data store

* posting to the same [metric / timestamp] combination with different tags overwrites datapoint
* not possible to clear metrics
* graphing options are rudimentary
  * [ HawkFX ]( https://github.com/pilhuhn/hawkfx ) is a native UI
  * [ Grafana Plugin ](https://github.com/hawkular/hawkular-grafana-datasource) with limitations
    * [no aggregations](https://github.com/hawkular/hawkular-grafana-datasource/issues/79)

## Running specs

```bash
docker-compose up
```

This will give you hawkular metrics and grafana. Then execute the specs as this:

```
❯ be rspec --format d spec.rb
"Tenant: miq-30833"
"name:cpu/resource_type:Vm/resource_id:01/host:01/ems:01"
"name:power/resource_type:Vm/resource_id:01/host:01/ems:01"
"name:cpu/resource_type:Vm/resource_id:02/host:01/ems:01"
"name:power/resource_type:Vm/resource_id:02/host:01/ems:01"
"name:cpu/resource_type:Vm/resource_id:03/host:02/ems:02"
"name:power/resource_type:Vm/resource_id:03/host:02/ems:02"

Randomized with seed 55993

MetricStore
  aggregate vm data to a host
  downsample 15 minute granularity data to 1 hour buckets
  graph the number of vms running on a host (PENDING: FAILS: There is currently no API for fetching bucket data points across multiple availability metrics.)
  upsample 15 minute granularity data to 5 minute buckets with interpolated data (PENDING: FAILS: returns empty buckets and buckets with 1 sample)
  graph the max of cpu usage of all vms

Pending: (Failures listed here are expected and do not affect your suite's status)

  1) MetricStore graph the number of vms running on a host
     # FAILS: There is currently no API for fetching bucket data points across multiple availability metrics.
     Failure/Error: expect(buckets).not_to be_empty
       expected `[].empty?` to return false, got true
     # ./spec.rb:147:in `block (2 levels) in <top (required)>'

  2) MetricStore upsample 15 minute granularity data to 5 minute buckets with interpolated data
     # FAILS: returns empty buckets and buckets with 1 sample
     Failure/Error: expect(buckets).to all(include('samples' => 1))

       expected [{"start" => 1499854619000, "end" => 1499854919000, "min" => 0.7787604373475308, "avg" => 0.7787604373475308,...391470922786, "max" => 0.27189391470922786, "sum" => 0.27189391470922786, "samples" => 1, "empty" => false}] to all include {"samples" => 1}

          object at index 1 failed to match:
             expected {"start" => 1499854919000, "end" => 1499855219000, "empty" => true} to include {"samples" => 1}

          object at index 2 failed to match:
             expected {"start" => 1499855219000, "end" => 1499855519000, "empty" => true} to include {"samples" => 1}
     # ./spec.rb:126:in `block (2 levels) in <top (required)>'

Finished in 0.27122 seconds (files took 0.60814 seconds to load)
5 examples, 0 failures, 2 pending

Randomized with seed 55993

```