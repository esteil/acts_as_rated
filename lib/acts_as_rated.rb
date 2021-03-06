# ActsAsRated
module ActsAsRated
  def self.included(base)
    base.send :extend, ClassMethods
  end
  
  module ClassMethods
    # Enables rating methods on this class
    #
    # The supported options are:
    #
    # +:ignore_type+ set to +true+ if rankings should not be scoped via STI type.
    def acts_as_rated(opts={}, &block) 
      class_inheritable_accessor :rating_rules
      class_inheritable_accessor :acts_as_rated_ignores_type
      
      self.acts_as_rated_ignores_type = !!opts[:ignore_type]
      
      self.rating_rules = ActsAsRated::RatedRules.new
      self.rating_rules.instance_exec &block
  
      send :extend, SingletonMethods
      send :include, InstanceMethods
    end
  end
  
  module SingletonMethods
    def update_rankings
      self.transaction do
        # select u.id, u.type, u.raw_rating, (
        #   IF(raw_rating = 0, 0,
        #     -- else calculate it
        #     GREATEST(1, FLOOR(raw_rating / (SELECT MAX(raw_rating) / 100 FROM users WHERE type = u.type)))
        #   )
        # ) AS ranking
        # FROM users u
        # ORDER BY type, ranking DESC;

        type_str = nil
        if self.column_names.include? self.inheritance_column
          the_sti_name = (sti_name == self.base_class.name ? '' : nil)
          type_str = sanitize_sql_for_conditions(["#{connection.quote_table_name table_name}.#{connection.quote_column_name inheritance_column} = ?", the_sti_name]) if the_sti_name
        end unless self.acts_as_rated_ignores_type
        
        max_rating = self.maximum(:raw_rating, :conditions => type_str) || 0
        min_rating = self.minimum(:raw_rating, :conditions => "#{type_str ? type_str + " AND" : ''} raw_rating > 0") || 0
        scale_factor = (max_rating - min_rating) / 100.0
        scale_factor = 1.0 if scale_factor == 0

        # This will update all the rankings, if the rating is 0 they get a ranking of 0, otherwise if they've had
        # any activity at all that gets rated they get at least a 1 ranking.
        self.update_all [%{#{table_name}.ranking = IF(#{table_name}.raw_rating = 0, 0, 
          -- calculate it here, and make sure it's a 1 if the score isn't 0
          GREATEST(1, ROUND(
            (#{table_name}.raw_rating - ?) / ?
          ))
        )}, min_rating, scale_factor], type_str
      end
    end
  end
  
  module InstanceMethods
    def evaluate_rating
      self.rating_rules.evaluate_rules(self)
    end
    
    def calculate_rating
      self.transaction do
        new_rating = evaluate_rating[0]
      
        # Update_all is used to bypass any callbacks
        self.class.update_all ['raw_rating = ?', new_rating], ['id = ?', self.id]
      end
    end
    
    def explain_rating(full = false)
      self.transaction do
        final_score, rating_reasons = evaluate_rating
        reasons = []
      
        rating_reasons.each do |reason|
          delta, reason_text, score = *reason
        
          reasons << '%+7d | %-60.60s' % reason if full or delta != 0
        end
      
        reasons.join("\n") + ("\n" + '-' * 70 + "\n%7d <-- Final rating" % final_score)
      end
    end
  end
end

ActiveRecord::Base.send :include, ActsAsRated
