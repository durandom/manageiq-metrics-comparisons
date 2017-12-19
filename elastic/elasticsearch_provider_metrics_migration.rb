#!/usr/bin/env ruby

# A migration script moving provider metrics (metrics and metric_rollups tables) from Postgresql to Elasticsearch

require File.expand_path('../config/environment', __dir__)
require 'elasticsearch'

es_client = Elasticsearch::Client.new

migratable_metric_columns = Metric.column_names.reject! do |name|
  %w(id created_on capture_interval capture_interval_name).include?(name) || name.include?("derived_")
end

# Hashes of attributes to be migrated
data = Metric.pluck(*migratable_metric_columns).map do |attr_set|
  attrs = Hash[migratable_metric_columns.zip(attr_set)]
  attrs.reject! do |_k, v|
    no_value = v.blank? && !(v == false)
    zero = v == 0 # TODO: This might be improper. I feel like some columns are coerced to 0 on nil data and not meaningful, but that needn't be all 0's.

    no_value || zero
  end

  attrs
end

# Format hashes for ES
es_data = data.map do |attr_set|
  Hash[:index => { :data => attr_set }]
end

es_client.bulk(:index => 'provider-metrics', :type => 'realtime', :body => es_data)

puts "Done."

