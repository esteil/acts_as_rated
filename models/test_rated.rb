class TestRated < ActiveRecord::Base
  acts_as_rated do
    # Rating definitions here
    desc "Add 10 points if OK"
    add 10, :if => :ok
    
    desc "Add 10 points if not OK"
    add 10, :if => :not_ok
    
    desc "Add -10 points unless not ok"
    add -10, :unless => :not_ok
    
    desc "Add age"
    add do
      52 * age
    end
    
    desc "+1 each attendee"
    add 1, :count => :num_attendees
    
    desc "8x thing value"
    add 8, :count => :thing
  end
  
  def ok
    true
  end
  
  def not_ok
    false
  end
  
  def age
    23
  end
  
  def num_attendees
    5
  end
end
