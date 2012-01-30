module ActiveRecord
  module Acts
    module HappyTree
      module BreadthFirst

        def each_level_ids(options={})
          level_ids = [id]
          until level_ids.empty?
            level_ids = self.class.child_ids_of(level_ids, options)
            yield level_ids
          end
        end

        def each_level_nodes(options={})
          level_nodes = [self]
          until level_nodes.empty?
            ids = level_nodes.map(&:id)
            level_nodes = self.class.children_of(ids, options)
            yield level_nodes
          end
        end

        # Returns a flat list of the descendants of the current node using a
        # breadth-first search http://en.wikipedia.org/wiki/Breadth-first_search
        #
        #   root.descendants_bfs # => [child1, child2, subchild1, subchild2]
        # options can be passed such as:
        #   select - only return specified attributes, must include id
        #   conditions - only return matching objects, will not return children
        #                of any unmatched objects
        #   order - will set the order of each set of children
        #   limit - will limit max number of children for each parent
        #
        # number of DB calls == number of levels
        # for the example there will be 3 DB calls
        def descendants_bfs(options={})
          desc_nodes = []
          each_level_nodes(options) do |nodes|
            desc_nodes += nodes
          end
          return desc_nodes
        end

        # Returns a flat list of the descendant ids of the current node using a
        # breadth-first search http://en.wikipedia.org/wiki/Breadth-first_search
        # DB calls = level of tree
        # only id field returned in query
        def descendant_ids_bfs(options={})
          desc_ids = []
          each_level_ids(options) do |level_ids|
            desc_ids += level_ids
          end
          return desc_ids
        end

        # Return the number of descendants
        # DB calls = level of tree
        # only id field selected in query
        def descendants_count_bfs(options={})
          count = 0
          each_level_ids(options) do |level_ids|
            count += level_ids.count
          end
          return count
        end

        # Return all descendants and current node, this is present for
        # completeness with other tree implementations
        def self_and_descendants_bfs(options={})
          [self] + descendants_bfs(options)
        end

        def descendant_ids_bfs_rec(options={})
          descendants_bfs_rec(options.merge(:select=>'id')).map(&:id)
        end

        def descendants_bfs_rec(options={})
          c = children.all(options)
          c + c.map do |child|
            child.descendants_bfs_rec(options)
          end.flatten
        end

        def descendants_count_bfs_rec(options={})
          children.count + children.all(options.merge(:select=>'id')).reduce(0) do |count, child|
            count += child.descendants_count_bfs_rec(options)
          end
        end

      end
    end
  end
end
