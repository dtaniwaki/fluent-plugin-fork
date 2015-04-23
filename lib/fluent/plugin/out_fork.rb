module Fluent
  class ForkOutput < Output
    class MaxForkSizeError < StandardError; end

    Fluent::Plugin.register_output('fork', self)

    unless method_defined?(:log)
      define_method(:log) { $log }
    end

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

    def configure(conf)
      super

      fallbacks = %w(skip drop log)
      raise Fluent::ConfigError, "max_fallback must be one of #{fallbacks.inspect}" unless fallbacks.include?(@max_fallback)
    end

    def emit(tag, es, chain)
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

        values.reject{ |value| value.to_s == '' }.each do |value|
          log.trace "#{tag} - #{time}: reemit #{@output_key}=#{value} for #{@output_tag}"
          Engine.emit(@output_tag, time, record.reject{ |k, v| k == @fork_key }.merge(@output_key => value))
        end
      end
    rescue => e
      log.error "#{e.message}: #{e.backtrace.join(', ')}"
    ensure
      chain.next
    end
  end
end
