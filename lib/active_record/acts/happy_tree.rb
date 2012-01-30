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
      #    \_ child2
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
            include ActiveRecord::Acts::HappyTree::BreadthFirst
            include ActiveRecord::Acts::HappyTree::DepthFirst

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

            def self.parent_key
              "#{configuration[:foreign_key]}"
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

        # AR >= 3.2 only
        def pluck_parent_id_of(node_id)
          where(:id=>node_id).pluck(parent_key).first
        end

        def pluck_child_ids_of(node_ids, options={})
          where(parent_key=>node_ids).apply_finder_options(options).pluck(:id)
        end

        # AR >= 3.0 only
        def select_parent_id_of(node_id)
          where(:id=>node_id).select(parent_key).first[parent_key]
        end

        def select_child_ids_of(node_ids, options={})
          where(parent_key=>node_ids).apply_finder_options(options.merge(:select=>:id)).map(&:id)
        end

        if ActiveRecord::Base.respond_to?(:pluck)
          alias :parent_id_of :pluck_parent_id_of
          alias :child_ids_of :pluck_child_ids_of
        else
          alias :parent_id_of :select_parent_id_of
          alias :child_ids_of :select_child_ids_of
        end

        def children_of(node_ids, options={})
          where(parent_key=>node_ids).apply_finder_options(options)
        end

      end

      module InstanceMethods

        # Returns list of ancestors, starting from parent until root.
        #
        #   subchild1.ancestors # => [child1, root]
        def ancestors
          node, nodes = self, []
          nodes << node = node.parent until node.parent.nil? and return nodes
        end

        # Returns the root node of the tree.
        def root_classic
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

        # Returns true if this instance has no parent (aka root node)
        #
        # root.root? # => true
        # child1.root? # => false
        #
        # no DB access
        def root?
          tree_parent_key.nil?
        end

        # Returns true if this instance has a parent (aka child node)
        #
        # root.child? # => false
        # child1.child? # => true
        #
        # no DB access
        def child?
          !tree_parent_key.nil?
        end

        # returns true if this instance has any children (aka parent node)
        #
        # root.parent? # => true
        # subchild1.parent? # => false
        #
        # 1 DB SELECT, no fields selected
        def parent?
          children.exists?
        end

        # returns true if this instance has no children (aka leaf node)
        #
        # root.leaf? # => false
        # subchild1.leaf? # => true
        #
        # 1 DB SELECT, no fields selected
        def leaf?
          !children.exists?
        end

        # Returns true if this instance is an ancestor of another instance
        #
        # root.ancestor_of?(child1) # => true
        # child1.ancestor_of?(root) # => false
        #
        # 1 DB SELECT per level examined, only selects "parent_id"
        # AR <  3.2 = 1 AR object per level examined
        # AR >= 3.2 = no AR objects
        def ancestor_of?(node)
          key = node.tree_parent_key
          until key.nil? do
            return true if key == id
            key = self.class.parent_id_of(key)
          end
          return false
        end

        # Returns true if this instance is a descendant of another instance
        #
        # root.descendant_of?(child1) # => false
        # child1.descendant_of?(root) # => true
        #
        # calls ancestor_of? as:
        #   node1.ancestor_of(node2) == node2.descendant_of(node1)
        #
        # same performance of ancestor_of?
        def descendant_of?(node)
          node.ancestor_of?(self)
        end

        # Returns list of ancestor ids, starting from parent until root.
        #
        #   subchild1.ancestors # => [child1.id, root.id]
        #
        # 1 DB SELECT per ancestor, only selects "parent_id"
        # AR <  3.2 = 1 AR object per ancestor
        # AR >= 3.2 = 0 AR objects
        def ancestor_ids
          key, node_ids = tree_parent_key, []
          until key.nil? do
            node_ids << key
            key = self.class.parent_id_of(key)
          end
          return node_ids
        end

        # Returns the root id of the current node
        # no DB access if node is root
        # otherwise use root_id function which is optimized
        # 1 DB SELECT per ancestor, only selects "parent_id"
        # AR <  3.2 = 1 AR object per ancestor
        # AR >= 3.2 = 1 AR object total
        def root_id
          node_id = id
          key = tree_parent_key
          until key.nil? do
            node_id = key
            key = self.class.parent_id_of(key)
          end
          return node_id
        end

        # Returns the root node of the current node
        # no DB access if node is root
        # otherwise use root_id function which is optimized
        # same performance as root_id
        # other acts_as_tree variants select all fields and instantiate all objects
        def root
          root? ? self : self.class.find(root_id)
        end

        # return self and descendants
        # provided for compatibility with other tree implementations
        # expected order is DFS
        def self_and_descendants(options={})
          self_and_descendants_dfs(options)
        end

        # return an array of descendant ids
        # expected order is DFS
        def descendant_ids(options={})
          descendant_ids_dfs(options)
        end

        # Use BFS for descendants_count because it should use fewer SQL queries
        # and thus be faster
        def descendants_count(options={})
          descendants_count_bfs(options)
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
          self.class.parent_key
        end

        def tree_parent_key
          attributes[tree_parent_key_name]
        end

      end
    end
  end
end
