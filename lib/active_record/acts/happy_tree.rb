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

          validate :parent_key_must_be_valid

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
        def descendants_classic(node=self)
          nodes = []
          nodes << node unless node == self

          node.children.each do |child|
            nodes += descendants_classic(child)
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
        #
        # equivalent of node.descendant_of?(self)
        # node1.ancestor_of(node2) == node2.descendant_of(node1)
        def ancestor_of?(node)
          return false if (node.nil? || !node.is_a?(self.class))
          key = node.tree_parent_key
          until key.nil? do
            return true if key == self.id
            key = self.class.parent_id_of(key)
          end
          return false
        end

        # Returns true if this instance is a descendant of another instance
        #
        # root.descendant_of?(child1) # => false
        # child1.descendant_of?(root) # => true
        #
        # same performance as ancestor_of?
        # 
        # equivalent of node.ancestor_of?(self)
        # node1.descendant_of(node2) == node2.ancestor_of(node1)
        def descendant_of?(node)
          return false if (node.nil? || !node.is_a?(self.class))
          key = self.tree_parent_key
          until key.nil? do
            return true if key == node.id
            key = self.class.parent_id_of(key)
          end
          return false
        end

        # Returns list of ancestor ids, starting from parent until root.
        #
        #   subchild1.ancestor_ids # => [child1.id, root.id]
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

        # Returns a count of the number of ancestors
        #
        #   subchild1.ancestors_count # => 2
        #
        # 1 DB SELECT per ancestor, only selects "parent_id"
        # AR <  3.2 = 1 AR object per ancestor
        # AR >= 3.2 = 0 AR objects
        def ancestors_count
          key, count = tree_parent_key, 0
          until key.nil? do
            count += 1
            key = self.class.parent_id_of(key)
          end
          return count
        end

        # Returns the root id of the current node
        # no DB access if node is root
        # otherwise use root_id function which is optimized
        # 1 DB SELECT per ancestor, only selects "parent_id"
        # AR <  3.2 = 1 AR object per ancestor
        # AR >= 3.2 = 0 AR objects
        def root_id
          key, node_id = tree_parent_key, id
          until key.nil? do
            node_id = key
            key = self.class.parent_id_of(key)
          end
          return node_id
        end

        # Returns the root node of the current node
        # no DB access if node is root
        # otherwise use root_id function which is optimized
        # performance = root_id + 1 DB SELECT and 1 AR object if not root
        # other acts_as_tree variants select all fields and instantiate all objects
        def root
          root? ? self : self.class.find(root_id)
        end

        # helper method to allow the choosing of the descendants traversal
        # method by setting :traversal option as follows:
        #
        # :classic - depth-first search, recursive
        #          - only for descendants, ignores finder options
        # :dfs - depth-first search, iterative
        # :dfs_rec - depth-first search, recursive
        # :bfs - breadth-first search, interative
        # :bfs_rec - breadth-first search, recursive
        def descendants_call(method, default, options={})
          traversal = options.delete(:traversal)
          case traversal
          when :classic
            send("#{method}_classic")
          when :bfs, :dfs, :bfs_rec, :dfs_rec
            send("#{method}_#{traversal}", options)
          else
            send("#{method}_#{default}", options)
          end
        end

        # returns all of the descendants
        # uses iterative method in DFS order by default
        # options are finder options
        def descendants(options={})
          descendants_call(:descendants, :dfs, options)
        end

        # return self and descendants
        # provided for compatibility with other tree implementations
        # uses iterative method in DFS order by default
        # options are finder options
        def self_and_descendants(options={})
          descendants_call(:self_and_descendants, :dfs, options)
        end

        # return an array of descendant ids
        # uses iterative method in DFS order by default
        # options are finder options
        def descendant_ids(options={})
          descendants_call(:descendant_ids, :dfs, options)
        end

        # return a count of the number of descendants
        # Use BFS for descendants_count because it should use fewer SQL queries
        # and thus be faster
        # options are finder options
        def descendants_count(options={})
          descendants_call(:descendants_count, :bfs, options)
        end

        # method for validating parent_key to make sure it is not
        # 1) the same as id
        # 2) already a descendant of the current node
        def parent_key_must_be_valid
          return if id.nil?
          if (tree_parent_key==id)
            errors.add(tree_parent_key_name, "#{tree_parent_key_name} cannot be the same as id")
          elsif ancestor_of?(parent)
            errors.add(tree_parent_key_name, "#{tree_parent_key_name} cannot be a descendant")
          end
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
