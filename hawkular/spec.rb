require 'hawkular/hawkular_client'
require 'awesome_print'
require 'byebug'
require 'active_support/all'
require 'rspec'

class MetricStore
  attr_accessor :client

  def initialize
    tenant = "miq-#{$$}"
    @client = Hawkular::Client.new(
        entrypoint: 'http://localhost:8080',
        credentials: { username: 'jdoe', password: 'password' },
        options: { tenant: tenant}
    )
    ap "Tenant: #{tenant}"
  end

  def add_metric(tags, type = 'gauges')
    metric_name = tags.map{|k,v| "#{k}:#{v}" }.join('/')
    begin
      @client.metrics.send(type).create(id: metric_name, tags: tags)
    rescue => e
      p e.message
      raise unless e.message =~ /already exists/
    end
    metric_name
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
  attr_accessor :id, :host
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

ems_1 = Ems.new(id: '01', metrics_granularity: 15) # minutes capture granularity
ems_2 = Ems.new(id: '02', metrics_granularity: 30)

host_1 = Host.new(id: '01', ems: ems_1)
host_2 = Host.new(id: '02', ems: ems_2)

vm_1 = Vm.new(id: '01', host: host_1)
vm_2 = Vm.new(id: '02', host: host_1)
vm_3 = Vm.new(id: '03', host: host_2)

vms = [vm_1, vm_2, vm_3]
ends = DateTime.now
starts = ends - 3.hours
store = MetricStore.new

vms.each do |vm|
  # add cpu metric (gauge)
  tags = {
      name: 'cpu',
      resource_type: 'Vm',
      resource_id: vm.id,
      host: vm.host.id,
      ems: vm.ems.id,
  }
  metrics_granularity = vm.ems.metrics_granularity

  ap metric_name = store.add_metric(tags)

  metric_data = (starts.to_i..ends.to_i).step(metrics_granularity*60).map do |timestamp|
    {
        :timestamp => timestamp * 1000,
        :value => rand
    }
  end

  store.client.metrics.gauges.push_data(metric_name, metric_data)

  # add power state metric (gauge)
  tags[:name] = 'power'
  ap metric_name = store.add_metric(tags, 'avail')
  metric_data = (starts.to_i..ends.to_i).step(metrics_granularity*60).map do |timestamp|
    {
        :timestamp => timestamp * 1000,
        :value => %w(up down unknown).sample
    }
  end
  store.client.metrics.avail.push_data(metric_name, metric_data)
end


describe MetricStore do
  it 'downsample 15 minute granularity data to 1 hour buckets' do
    # requests 2 hours range in 1hr bucket duration
    buckets = store.client.metrics.gauges.get_data_by_tags({resource_type: 'Vm', resource_id: vm_1.id, name: 'cpu'},
                                                           starts: starts.to_i*1000,
                                                           ends: (starts+2.hours).to_i*1000,
                                                           bucketDuration: '1h')

    expect(buckets.count).to eq(2)
    expect(buckets).to all(include('samples' => 4))
  end

  it 'upsample 15 minute granularity data to 5 minute buckets with interpolated data' do
    pending("FAILS: returns empty buckets and buckets with 1 sample")
    # requests 20 minute range in 5 mn bucket duration
    buckets = store.client.metrics.gauges.get_data_by_tags({resource_type: 'Vm', resource_id: vm_1.id, name: 'cpu'},
                                                    starts: starts.to_i*1000,
                                                    ends: (starts+20.minutes).to_i*1000,
                                                    bucketDuration: '5mn')
    expect(buckets.count).to eq(4)
    expect(buckets).to all(include('samples' => 1))
  end

  it 'aggregate vm data to a host' do
    buckets = store.client.metrics.gauges.get_data_by_tags({host: host_1.id, name: 'cpu'},
                                                              starts: starts.to_i*1000,
                                                              ends: (starts+1.hours).to_i*1000,
                                                              bucketDuration: '15mn')
    expect(buckets.count).to eq(4)
    # raw data was at the same granularity, so every bucket contains a sample from each vm
    # and this host has 2 vms on it
    expect(buckets).to all(include('samples' => 2))
  end

  it 'graph the number of vms running on a host' do
    pending("FAILS: There is currently no API for fetching bucket data points across multiple availability metrics.")
    metrics = store.client.metrics.avail.query({host: host_1.id, name: 'power'})
    buckets = store.client.metrics.avail.get_data_by_tags({host: host_1.id, name: 'power'},
                                                             starts: starts.to_i*1000,
                                                             ends: (starts+1.hours).to_i*1000,
                                                             bucketDuration: '15mn')
    expect(buckets).not_to be_empty
  end

  it 'graph the max of cpu usage of all vms' do
    buckets = store.client.metrics.gauges.get_data_by_tags({resource_type: 'Vm', name: 'cpu'},
                                                              starts: (ends - 360.days).to_i * 1000,
                                                              ends: ends.to_i * 1000,
                                                              # works, but is missing in ruby client
                                                              # percentiles: '75,90,99',
                                                              bucketDuration: '360d')
    expect(buckets.count).to eq(1)
  end
end

