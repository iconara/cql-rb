# encoding: utf-8

module Cql
  module Client
    # @private
    class DataCenterAwareConnectionStrategy
      def initialize(data_centers)
        @data_centers = data_centers
      end

      def connect?(peer_info)
        @data_centers.include?(peer_info['data_center'])
      end
    end
  end
end
