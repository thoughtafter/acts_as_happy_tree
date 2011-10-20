module ActiveRecord
  module Acts
    module HappyTree
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Specify this +acts_as+ extension if you want to model a tree structure by providing a parent association and a children
      # association. This requires that you have a foreign key column, which by default is called +parent_id+.
      #
      #   class Category < ActiveRecord::Base
      #     acts_as_happy_tree :order => "name"
      #   end
      #
      #   Example:
      #   root
      #    \_ child1
      #         \_ subchild1
      #         \_ subchild2
      #
      #   root      = Category.create("name" => "root")
      #   child1    = root.children.create("name" => "child1")
      #   subchild1 = child1.children.create("name" => "subchild1")
      #
      #   root.parent   # => nil
      #   child1.parent # => root
      #   root.children # => [child1]
      #   root.children.first.children.first # => subchild1
      #
      # In addition to the parent and children associations, the following instance methods are added to the class
      # after calling <tt>acts_as_happy_tree</tt>:
      # * <tt>siblings</tt> - Returns all the children of the parent, excluding the current node (<tt>[subchild2]</tt> when called on <tt>subchild1</tt>)
      # * <tt>self_and_siblings</tt> - Returns all the children of the parent, including the current node (<tt>[subchild1, subchild2]</tt> when called on <tt>subchild1</tt>)
      # * <tt>ancestors</tt> - Returns all the ancestors of the current node (<tt>[child1, root]</tt> when called on <tt>subchild2</tt>)
      # * <tt>root</tt> - Returns the root of the current node (<tt>root</tt> when called on <tt>subchild2</tt>)
      # * <tt>descendants</tt> - Returns a flat list of the descendants of the current node (<tt>[child1, subchild1, subchild2]</tt> when called on <tt>root</tt>)
      module ClassMethods
        # Configuration options are:
        #
        # * <tt>foreign_key</tt> - specifies the column name to use for tracking of the tree (default: +parent_id+)
        # * <tt>order</tt> - makes it possible to sort the children according to this SQL snippet.
        # * <tt>counter_cache</tt> - keeps a count in a +children_count+ column if set to +true+ (default: +false+).
        def acts_as_happy_tree(options = {})
          configuration = { :foreign_key => "parent_id", :order => nil, :counter_cache => nil, :dependent => :destroy, :touch => false }
          configuration.update(options) if options.is_a?(Hash)

          belongs_to :parent, :class_name => name, :foreign_key => configuration[:foreign_key], :counter_cache => configuration[:counter_cache], :touch => configuration[:touch]
          has_many :children, :class_name => name, :foreign_key => configuration[:foreign_key], :order => configuration[:order], :dependent => configuration[:dependent]

          class_eval <<-EOV
            include ActiveRecord::Acts::HappyTree::InstanceMethods

            scope :roots, :conditions => "#{configuration[:foreign_key]} IS NULL", :order => #{configuration[:order].nil? ? "nil" : %Q{"#{configuration[:order]}"}}

            after_update :update_parents_counter_cache

            def self.root
              roots.first
            end

            def self.childless
              nodes = []

              find(:all).each do |node|
                nodes << node if node.children.empty?
              end

              nodes
            end

            validates_each "#{configuration[:foreign_key]}" do |record, attr, value|
              if value
                if record.id == value
                  record.errors.add attr, "cannot be it's own id"
                elsif record.descendants.map {|c| c.id}.include?(value)
                  record.errors.add attr, "cannot be a descendant's id"
                end
              end
            end
          EOV
        end
      end

      module InstanceMethods

        # Returns true if this instance has no parent (aka root node)
        #
        # root.root? # => true
        # child1.root? # => false
        #
        # 0 DB calls
        def root?
          tree_parent_key.nil?
        end

        # Returns true if this instance has a parent (aka child node)
        #
        # root.child? # => false
        # child1.child? # => true
        #
        # 0 DB calls
        def child?
          !tree_parent_key.nil?
        end

        # returns true if this instance has any children (aka parent node)
        #
        # root.parent? # => true
        # subchild1.parent? # => false
        #
        # 1 DB call
        def parent?
          children.exists?
        end

        # returns true if this instance has no children (aka leaf node)
        #
        # root.leaf? # => false
        # subchild1.leaf? # => true
        #
        # 1 DB call
        def leaf?
          !children.exists?
        end

        # Returns true if this instance is an ancestor of another instance
        #
        # root.ancestor_of?(child1) # => true
        # child1.ancestor_of?(root) # => false
        #
        # 1 DB call per level examined, only retrieves "parent_id" in each call
        def ancestor_of?(node)
          until node.tree_parent_key.nil? do
            return true if node.tree_parent_key == id
            node = self.class.where(:id=>node.tree_parent_key).select(tree_parent_key_name).first
          end
          return false
        end

        # Returns true if this instance is a descendant of another instance
        #
        # root.descendant_of?(child1) # => false
        # child1.descendant_of?(root) # => true
        #
        # 1 DB call per level examined, only retrieves "parent_id" in each call
        #
        # calls ancestor_of? as:
        #   node1.ancestor_of(node2) == node2.descendant_of(node1)
        def descendant_of?(node)
          node.ancestor_of?(self)
        end

        # Returns list of ancestors, starting from parent until root.
        #
        #   subchild1.ancestors # => [child1, root]
        def ancestors
          node, nodes = self, []
          nodes << node = node.parent until node.parent.nil? and return nodes
        end

        # Returns the root node of the tree.
        def root
          node = self
          node = node.parent until node.parent.nil? and return node
        end

        # Returns all siblings of the current node.
        #
        #   subchild1.siblings # => [subchild2]
        def siblings
          self_and_siblings - [self]
        end

        # Returns all siblings and a reference to the current node.
        #
        #   subchild1.self_and_siblings # => [subchild1, subchild2]
        def self_and_siblings
          parent ? parent.children : self.class.roots
        end

        # Returns a flat list of the descendants of the current node.
        #
        #   root.descendants # => [child1, subchild1, subchild2]
        def descendants(node=self)
          nodes = []
          nodes << node unless node == self

          node.children.each do |child|
            nodes += descendants(child)
          end

          nodes.compact
        end

        def childless
          self.descendants.collect{|d| d.children.empty? ? d : nil}.compact
        end

      private

        def update_parents_counter_cache
          if self.respond_to?(:children_count) && parent_id_changed?
            self.class.decrement_counter(:children_count, parent_id_was)
            self.class.increment_counter(:children_count, parent_id)
          end
        end

      protected

        def tree_parent_key_name
          reflections[:parent].options[:foreign_key]
        end

        def tree_parent_key
          attributes[tree_parent_key_name]
        end

      end
    end
  end
end
