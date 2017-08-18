require 'fluent/plugin/output'

module Fluent::Plugin
  class ForkOutput < Output
    class MaxForkSizeError < StandardError; end

    Fluent::Plugin.register_output('fork', self)

    helpers :event_emitter

    def initialize
      super
    end

    config_param :output_tag,    :string
    config_param :output_key,    :string
    config_param :fork_key,      :string
    config_param :fork_value_type, :string, default: 'csv'
    config_param :separator,     :string,  default: ','
    config_param :max_size,      :integer, default: nil
    config_param :max_fallback,  :string,  default: 'log'
    config_param :no_unique,     :bool,    default: false
    config_param :index_key,     :string,  default: nil

    def configure(conf)
      super

      fallbacks = %w(skip drop log)
      raise Fluent::ConfigError, "max_fallback must be one of #{fallbacks.inspect}" unless fallbacks.include?(@max_fallback)
    end

    def process(tag, es)
      es.each do |time, record|
        org_value = record[@fork_key]
        if org_value.nil?
          log.trace "#{tag} - #{time}: skip to fork #{@fork_key}=#{org_value}"
          next
        end
        log.trace "#{tag} - #{time}: try to fork #{@fork_key}=#{org_value}"

        values = []
        case @fork_value_type
        when 'csv'
          values = org_value.split(@separator)
        when 'array'
          values = org_value
        else
          values = org_value
        end

        values = values.uniq unless @no_unique

        if @max_size && @max_size < values.size
          case @max_fallback
          when 'skip'
            log.warn "#{tag} - #{time}: Skip too many forked values (max=#{@max_size}) : #{org_value}"
            next
          when 'drop'
            log.warn "#{tag} - #{time}: Drop too many forked values (max=#{@max_size}) : #{org_value}"
            values = values.take(@max_size)
          when 'log'
            log.info "#{tag} - #{time}: Too many forked values (max=#{@max_size}) : #{org_value}"
          end
        end

        values.reject{ |value| value.to_s == '' }.each_with_index do |value, i|
          log.trace "#{tag} - #{time}: reemit #{@output_key}=#{value} for #{@output_tag}"
          new_record = record.reject{ |k, v| k == @fork_key }.merge(@output_key => value)
          new_record.merge!(@index_key => i) unless @index_key.nil?
          router.emit(@output_tag, time, new_record)
        end
      end
    rescue => e
      log.error "#{e.message}: #{e.backtrace.join(', ')}"
    end
  end
end
