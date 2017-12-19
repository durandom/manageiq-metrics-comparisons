require 'elasticsearch'
require 'awesome_print'
require 'byebug'
require 'active_support/all'
require 'rspec'

require 'elasticsearch/dsl'
include Elasticsearch::DSL

class MetricStore
  attr_accessor :client, :test_run

  def initialize
    @test_run = ENV['INDEX'] ||  "metrics-#{$$}" # this is just to isolate this spec run from other runs
    @client   = Elasticsearch::Client.new log: false, hosts: ['http://elastic:changeme@localhost:9200']
    ap "test prefix: #{@test_run}"
    template =<<EOT
{
  "template": "metrics-*",
  "settings": {
    "index": {
      "refresh_interval": "1s"
    }
  },
  "mappings": {
    "_default_": {
      "dynamic_templates": [
        {
          "strings": {
            "match": "*",
            "match_mapping_type": "string",
            "mapping":   { "type": "string",  "doc_values": true, "index": "not_analyzed" }
          }
        }
      ],
      "properties": {
        "@timestamp":    { "type": "date",    "doc_values": true },
        "count":         { "type": "integer", "doc_values": true, "index": "no" },
        "m1_rate":       { "type": "float",   "doc_values": true, "index": "no" },
        "m5_rate":       { "type": "float",   "doc_values": true, "index": "no" },
        "m15_rate":      { "type": "float",   "doc_values": true, "index": "no" },
        "max":           { "type": "integer", "doc_values": true, "index": "no" },
        "mean":          { "type": "integer", "doc_values": true, "index": "no" },
        "mean_rate":     { "type": "float",   "doc_values": true, "index": "no" },
        "median":        { "type": "float",   "doc_values": true, "index": "no" },
        "min":           { "type": "float",   "doc_values": true, "index": "no" },
        "p25":           { "type": "float",   "doc_values": true, "index": "no" },
        "p75":           { "type": "float",   "doc_values": true, "index": "no" },
        "p95":           { "type": "float",   "doc_values": true, "index": "no" },
        "p98":           { "type": "float",   "doc_values": true, "index": "no" },
        "p99":           { "type": "float",   "doc_values": true, "index": "no" },
        "p999":          { "type": "float",   "doc_values": true, "index": "no" },
        "std":           { "type": "float",   "doc_values": true, "index": "no" },
        "value":         { "type": "float",   "doc_values": true, "index": "no" },
        "value_boolean": { "type": "boolean", "doc_values": true, "index": "no" },
        "value_string":  { "type": "string",  "doc_values": true, "index": "no" }
      }
    }
  }
}
EOT

    @client.indices.put_template name: 'metrics', body: JSON.parse(template)
  end

  def add_metric(data)
    @client.bulk index: "#{@test_run}", type: 'metrics', body: data
  end
end

class BaseFake
  def initialize(values)
    values.each do |k, v|
      self.send("#{k}=", v)
    end
    self
  end
end

class Vm < BaseFake
  attr_accessor :id, :host, :power_state
  def ems
    host.ems
  end
end

class Host < BaseFake
  attr_accessor :id, :ems
end

class Ems < BaseFake
  attr_accessor :id, :metrics_granularity
end

describe MetricStore do


  before :all do
    @ems_1 = Ems.new(id: '01', metrics_granularity: 15) # minutes capture granularity
    @ems_2 = Ems.new(id: '02', metrics_granularity: 30)

    @host_1 = Host.new(id: '01', ems: @ems_1)
    @host_2 = Host.new(id: '02', ems: @ems_2)

    @vm_1 = Vm.new(id: '01', host: @host_1, power_state: 'on')
    @vm_2 = Vm.new(id: '02', host: @host_1, power_state: 'off')
    @vm_3 = Vm.new(id: '03', host: @host_2, power_state: 'off')

    @vms = [@vm_1, @vm_2, @vm_3]
    @ends = DateTime.parse('2017-01-01 23:00:00')
    @starts = @ends - 3.hours
    @store = MetricStore.new
    @vms.each do |vm|
      # add cpu metric (gauge)
      tags = {
          name: 'cpu',
          resource_type: 'Vm',
          resource_id: vm.id,
          host: vm.host.id,
          ems: vm.ems.id,
          power_state: vm.power_state
      }
      metrics_granularity = vm.ems.metrics_granularity


      metric_data = (@starts.to_i..@ends.to_i).step(metrics_granularity*60).map do |timestamp|
        {
            :index => {
                :data => tags.merge({ :"@timestamp" => timestamp * 1000,
                                      :value => rand })
            }
        }
      end
      ap "vm: #{vm.id} - #{metric_data.count}"
      unless ENV['INDEX']
        @store.add_metric(metric_data)
      end

      # @store.client.metrics.gauges.push_data(metric_name, metric_data)
      #
      # # add power state metric (gauge)
      # tags[:name] = 'power'
      # ap cetric_name = @store.add_metric(tags, 'avail')
      # metric_data = (@starts.to_i..@ends.to_i).step(metrics_granularity*60).map do |timestamp|
      #   {
      #       :timestamp => timestamp * 1000,
      #       :value => %w(up down unknown).sample
      #   }
      # end
      # @store.client.metrics.avail.push_data(metric_name, metric_data)
    end
    # sleep 2
  end

  it 'downsample 15 minute granularity data to 1 hour buckets' do
    # requests 2 hours range in 1hr bucket duration

    vm_1 = @vm_1
    starts = @starts
    definition = search do
      query do
        bool do
          must {term resource_type: 'Vm'}
          must {term resource_id: vm_1.id}
          must {term name: 'cpu'}
          filter do
            range '@timestamp' do
              gte starts
              lt starts+2.hours
            end
          end
        end
      end
      aggregation :downsample do
        date_histogram do
          field '@timestamp'
          interval '1h'
          aggregation :avg do
            avg field: 'value'
          end
        end
      end
    end

    result = @store.client.search index: @store.test_run, body: definition
    expect(result['aggregations']['downsample']['buckets'].count).to eq(2)
    expect(result['aggregations']['downsample']['buckets']).to all(include('doc_count' => 4))
  end

  # it 'upsample 15 minute granularity data to 5 minute buckets with interpolated data' do
  #   basically possible through https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-pipeline.html
  # end
  #
  it 'aggregate vm data to a host' do
    host_1 = @host_1
    starts = @starts
    definition = search do
      query do
        bool do
          must {term resource_type: 'Vm'}
          must {term host: host_1.id}
          must {term name: 'cpu'}
          filter do
            range '@timestamp' do
              gte starts
              lt starts+1.hours
            end
          end
        end
      end
      aggregation :downsample do
        date_histogram do
          field '@timestamp'
          interval '15m'
          aggregation :avg do
            avg field: 'value'
          end
        end
      end
    end

    result = @store.client.search index: @store.test_run, body: definition
    expect(result['aggregations']['downsample']['buckets'].count).to eq(4)
    expect(result['aggregations']['downsample']['buckets']).to all(include('doc_count' => 2))
  end

  it 'graph the number of @vms running on a host' do
    host_1 = @host_1
    starts = @starts
    definition = search do
      query do
        bool do
          must {term resource_type: 'Vm'}
          must {term host: host_1.id}
          must {term power: 'cpu'}
          filter do
            range '@timestamp' do
              gte starts
              lt starts+1.hours
            end
          end
        end
      end
      aggregation :downsample do
        date_histogram do
          field '@timestamp'
          interval '15m'
          aggregation :avg do
            avg field: 'value'
          end
        end
      end
    end

    result = @store.client.search index: @store.test_run, body: definition
    expect(result['aggregations']['downsample']['buckets'].count).to eq(4)
    expect(result['aggregations']['downsample']['buckets']).to all(include('doc_count' => 2))
    metrics = @store.client.metrics.avail.query({host: @host_1.id, name: 'power'})
    buckets = @store.client.metrics.avail.get_data_by_tags({host: @host_1.id, name: 'power'},
                                                             @starts: @starts.to_i*1000,
                                                             @ends: (@starts+1.hours).to_i*1000,
                                                             bucketDuration: '15mn')
    expect(buckets).not_to be_empty
  end
  #
  # it 'graph the max of cpu usage of all @vms' do
  #   buckets = @store.client.metrics.gauges.get_data_by_tags({resource_type: 'Vm', name: 'cpu'},
  #                                                             @starts: (@ends - 360.days).to_i * 1000,
  #                                                             @ends: @ends.to_i * 1000,
  #                                                             # works, but is missing in ruby client
  #                                                             # percentiles: '75,90,99',
  #                                                             bucketDuration: '360d')
  #   expect(buckets.count).to eq(1)
  # end
end

