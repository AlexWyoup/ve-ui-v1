#require 'xml'
require 'open-uri'

#
# Configure the Ganglia URL and host in application.rb:
#   config.ganglia_web_url  = ENV['GANGLIA_WEB_URL']
#   config.ganglia_host     = ENV['GANGLIA_HOST']
#
# or use and environment variable:
#   GANGLIA_WEB_URL=http://localhost:8080 rails s
#
# Target Selection:
#   You need to know the cluster name, hostname and metric name. Usually its easy
#   to obtain these from the graph url directly.
#
#   example: hostname@cluster(metric-name)
#
module Sources
  module Datapoints
    class Ganglia < Sources::Datapoints::Base

      PORT = 8649

      def initialize
        @url_builder = GangliaUrlBuilder.new(Rails.configuration.ganglia_web_url)
        
      end

      def available?
        Rails.configuration.ganglia_web_url.present? && Rails.configuration.ganglia_host.present?
      end

      def get(options = {})
        puts "get entry"
        from    = (options[:from]).to_i
        to      = (options[:to] || Time.now).to_i       
         metric  = Rails.configuration.ganglia_graph_metric
        #targets = targets.reject(&:blank?)
        ganglia_datapoints = request_datapoints(from, to, metric)
        result = []   
          result << { "datapoints" => ganglia_datapoints }       
        raise Sources::Datapoints::NotFoundError if result.empty?
        result
      end

      def available_targets(options = {})
        pattern = options[:pattern] || ""
        limit   = (options[:limit] || 200).to_i

        cached_result = cached_get("ganglia") do
          parse_targets(request_available_targets)
        end

        result = pattern.present? ? cached_result.reject { |target| target !~ /#{pattern}/ }  : cached_result
        result.slice(0, limit)
      end

     
      private

      def parse_targets(xml)
        targets = []
        source = XML::Parser.string(xml)
        content = source.parse
        hosts = content.root.find('//CLUSTER/HOST')
        cluster = content.root.find_first('//CLUSTER').attributes['NAME']
        hosts.each do |host|
          host.find('./METRIC').each do |metric|
            targets << "#{host.attributes['NAME']}@#{cluster}(#{metric.attributes['NAME']})"
          end
        end
        targets
      end

      def request_available_targets
        Rails.logger.debug("Requesting available targets from #{Rails.configuration.ganglia_host}:#{PORT} ...")
        client = TCPSocket.open(Rails.configuration.ganglia_host, PORT)
        result = ""
        while line = client.gets
          result << line.chop
        end
        client.close
        result
      end

      def request_datapoints(from, to, target)        
         puts "request_datapoints"
        result = []       
          hash = @url_builder.datapoints_url(from, to, target)
          Rails.logger.debug("Requesting datapoints from #{hash[:url]} with params #{hash[:params]} ...")
          response = ::HttpService.request(hash[:url], :params => hash[:params])          
          if response == "null"
            result << []
          else
            result << response.first["datapoints"]            
          end       
        result
      end
end
    end
  end