require 'active_record/acts/breadth_first'
require 'active_record/acts/depth_first'
require 'active_record/acts/happy_tree'
ActiveRecord::Base.send :include, ActiveRecord::Acts::HappyTree
