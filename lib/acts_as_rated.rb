# ActsAsRated
module ActsAsRated
  def self.included(base)
    base.send :extend, ClassMethods
  end
  
  module ClassMethods
    def acts_as_rated(*opts, &block) 
      cattr_accessor :rating_rules
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

        max_rating = self.maximum(:raw_rating) || 0
        min_rating = self.minimum(:raw_rating, :conditions => 'raw_rating > 0') || 0
        scale_factor = (max_rating - min_rating) / 100.0
        scale_factor = 1.0 if scale_factor == 0

        # This will update all the rankings, if the rating is 0 they get a ranking of 0, otherwise if they've had
        # any activity at all that gets rated they get at least a 1 ranking.
        self.update_all [%{#{table_name}.ranking = IF(#{table_name}.raw_rating = 0, 0, 
          -- calculate it here, and make sure it's a 1 if the score isn't 0
          GREATEST(1, ROUND(
            (#{table_name}.raw_rating - ?) / ?
          ))
        )}, min_rating, scale_factor]
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
        
          reasons << '%+7d %-50.50s |%8d' % reason if full or delta != 0
        end
      
        reasons.join("\n") + ("\n" + '-' * 68 + "\n%7d <-- Final rating" % final_score)
      end
    end
  end
end

ActiveRecord::Base.send :include, ActsAsRated
