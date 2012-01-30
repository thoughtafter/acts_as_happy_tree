module ActiveRecord
  module Acts
    module HappyTree
      module DepthFirst

        def each_descendant_id(options={})
          node_ids = self.class.child_ids_of(id, options)
          until node_ids.empty?
            node_id = node_ids.shift
            yield node_id
            node_ids.unshift(*self.class.child_ids_of(node_id, options))
          end
        end

        def each_descendant_node(options={})
          nodes = self.class.children_of(id, options)
          until nodes.empty?
            node = nodes.shift
            yield node
            nodes.unshift(*self.class.children_of(node.id, options))
          end
        end

        # Returns a flat list of the descendants of the current node using a
        # depth-first search http://en.wikipedia.org/wiki/Depth-first_search
        #
        # root.descendants_dfs # => [child1, subchild1, subchild2, child2]
        # options can be passed such as:
        #   select - only return specified attributes, must include "parent_id"
        #   conditions - only return matching objects, will not return children
        #                of any unmatched objects
        #   order - will set the order of each set of children
        #   limit - will limit max number of children for each parent
        #
        # this is a recursive method
        # the number of DB calls == number of descendants + 1
        def descendants_dfs(options={})
          desc_nodes = []
          each_descendant_node(options) do |node|
            desc_nodes << node
          end
          return desc_nodes
        end

        # Returns a flat list of the descendant ids of the current node using a
        # depth-first search http://en.wikipedia.org/wiki/Depth-first_search
        # DB calls = number of descendants + 1
        # only id field returned in query
        def descendant_ids_dfs(options={})
          desc_ids = []
          each_descendant_id(options) do |id|
            desc_ids << id
          end
          return desc_ids
        end

        # Return the number of descendants
        # DB calls = # of descendants + 1
        # only id field selected in query
        def descendants_count_dfs(options={})
          count = 0
          each_descendant_id(options) do |id|
            count += 1
          end
          return count
        end

        # Return all descendants and current node, this is present for
        # completeness with other tree implementations
        def self_and_descendants_dfs(options={})
          [self] + descendants_dfs(options)
        end

        def descendant_ids_dfs_rec(options={})
          descendants_dfs_rec(options.merge(:select=>'id')).map(&:id)
        end

        def descendants_dfs_rec(options={})
          children.all(options).map do |child|
            [child] + child.descendants_dfs_rec(options)
          end.flatten
        end

        def descendants_count_dfs_rec(options={})
          children.all(options.merge(:select=>'id')).reduce(0) do |count, child|
            count += 1 + child.descendants_count_dfs_rec(options)
          end
        end

      end
    end
  end
end
