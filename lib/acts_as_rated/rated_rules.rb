module ActsAsRated
  class RatedRules
    unloadable
    
    cattr_accessor :ruleset
    cattr_accessor :next_description
    
    def initialize
      @ruleset = []
    end
    
    def add(*args, &block)
      if block_given?
        opts = args
        opts = {} if opts.empty?
        @ruleset << [:add, @next_description, opts, block]
      else
        num = args[0]
        opts = args[1] || {}

        @ruleset << [:add_value, @next_description, opts, num]
      end
      
      @next_description = nil
    end
    
    def desc(text)
      @next_description = text
    end
    
    def rules
      @ruleset
    end
    
    def evaluate_rules(obj)
      score = 0
      # Array of [delta, reason, total_score]
      steps = []
      
      @ruleset.each do |rule|
        type, description, opts, arg = *rule
        
        # Check the if/unless conditions specified
        do_it = true
        
        if opts[:if].is_a?(Symbol)
          do_it = obj.send(opts[:if])
        elsif opts[:if].is_a?(Proc)
          do_it = obj.instance_exec(&opts[:if])
        end
        
        if opts[:unless].is_a?(Symbol)
          do_it = !obj.send(opts[:unless])
        elsif opts[:unless].is_a?(Proc)
          do_it = !obj.instance_exec(&opts[:unless])
        end
        
        unless do_it
          steps << [0, "SKIPPED #{description}", score]
          next
        end
        
        # Calculate an appropriate multiplier if specified
        if opts[:count].is_a?(Symbol)
          multiplier = obj.send(opts[:count])
        elsif opts[:count].is_a?(Proc)
          multiplier = obj.instance_exec(&opts[:count])
        else
          multiplier = 1
        end
        
        case type
        
        # Added via a block, block result is score
        when :add
          num = obj.instance_exec(&arg)
          delta = num * multiplier
          score += delta
          steps << [delta, (multiplier > 1 ? "(#{arg} * #{multiplier}) " : '' ) + description, score]
          
        # Adding a static value if
        when :add_value
          delta = arg * multiplier
          score += delta
          steps << [delta, (multiplier > 1 ? "(#{arg} * #{multiplier}) " : '' ) + description, score]
          
        else
          # Don't do anything
          
          steps << [0, "Unknown type: #{type} (#{description})", score]
        end
      end
      
      [score, steps]
    end
  end
end
