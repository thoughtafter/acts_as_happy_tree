require 'test/unit'

require 'rubygems'
require 'active_record'

$:.unshift File.dirname(__FILE__) + '/../lib'
require File.dirname(__FILE__) + '/../init'

class Test::Unit::TestCase
  def assert_queries(num = 1)
    $query_count = 0
    yield
  ensure
    assert_equal num, $query_count, "#{$query_count} instead of #{num} queries were executed."
  end

  def assert_no_queries(&block)
    assert_queries(0, &block)
  end
end

ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")

# AR keeps printing annoying schema statements
$stdout = StringIO.new

def setup_db
  ActiveRecord::Base.logger
  ActiveRecord::Schema.define(:version => 1) do
    create_table :mixins do |t|
      t.column :type, :string
      t.column :parent_id, :integer
      t.column :children_count, :integer, :default => 0
    end
  end
end

def teardown_db
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.drop_table(table)
  end
end

class Mixin < ActiveRecord::Base
end

class TreeMixin < Mixin
  acts_as_happy_tree :foreign_key => "parent_id", :order => "id"
end

class TreeMixinWithCounterCache < Mixin
  acts_as_happy_tree :foreign_key => "parent_id", :order => "id", :counter_cache => :children_count
end

class TreeMixinWithoutOrder < Mixin
  acts_as_happy_tree :foreign_key => "parent_id"
end

class RecursivelyCascadedTreeMixin < Mixin
  acts_as_happy_tree :foreign_key => "parent_id"
  has_one :first_child, :class_name => 'RecursivelyCascadedTreeMixin', :foreign_key => :parent_id
end

class TreeMixinNullify < Mixin
  acts_as_happy_tree :foreign_key => "parent_id", :order => "id", :dependent => :nullify
end

class TreeTest < Test::Unit::TestCase

  def setup
    setup_db
    @root1 = TreeMixin.create!
    @root_child1 = TreeMixin.create! :parent_id => @root1.id
    @child1_child = TreeMixin.create! :parent_id => @root_child1.id
    @root_child2 = TreeMixin.create! :parent_id => @root1.id
    @root2 = TreeMixin.create!
    @root3 = TreeMixin.create!
    @root_child1.reload # need to reload to recognize children
  end

  def teardown
    teardown_db
  end

  def test_children
    assert_equal @root1.reload.children, [@root_child1, @root_child2]
    assert_equal @root_child1.reload.children, [@child1_child]
    assert_equal @child1_child.reload.children, []
    assert_equal @root_child2.reload.children, []
  end

  def test_parent
    assert_equal @root_child1.parent, @root1
    assert_equal @root_child1.parent, @root_child2.parent
    assert_nil @root1.parent
  end

  def test_nullify
    root4 = TreeMixinNullify.create!
    root4_child = TreeMixinNullify.create! :parent_id => root4.id
    assert_equal 2, TreeMixinNullify.count
    assert_equal root4.id, root4_child.parent_id
    root4.destroy
    assert_equal 1, TreeMixinNullify.count
    assert_nil root4_child.reload.parent_id
  end

  def test_delete
    assert_equal 6, TreeMixin.count
    @root1.destroy
    assert_equal 2, TreeMixin.count
    @root2.destroy
    @root3.destroy
    assert_equal 0, TreeMixin.count
  end

  def test_insert
    @extra = @root1.children.create

    assert @extra

    assert_equal @extra.parent, @root1

    assert_equal 3, @root1.reload.children.count
    assert @root1.children.include?(@extra)
    assert @root1.children.include?(@root_child1)
    assert @root1.children.include?(@root_child2)
  end

  def test_ancestors
    assert_equal [], @root1.ancestors
    assert_equal [@root1], @root_child1.ancestors
    assert_equal [@root_child1, @root1], @child1_child.ancestors
    assert_equal [@root1], @root_child2.ancestors
    assert_equal [], @root2.ancestors
    assert_equal [], @root3.ancestors
  end

  def test_root
    assert_equal @root1, TreeMixin.root
    assert_equal @root1, @root1.root
    assert_equal @root1, @root_child1.root
    assert_equal @root1, @child1_child.root
    assert_equal @root1, @root_child2.root
    assert_equal @root2, @root2.root
    assert_equal @root3, @root3.root
  end

  def test_roots
    assert_equal [@root1, @root2, @root3], TreeMixin.roots
  end

  def test_siblings
    assert_equal [@root2, @root3], @root1.siblings
    assert_equal [@root_child2], @root_child1.siblings
    assert_equal [], @child1_child.siblings
    assert_equal [@root_child1], @root_child2.siblings
    assert_equal [@root1, @root3], @root2.siblings
    assert_equal [@root1, @root2], @root3.siblings
  end

  def test_self_and_siblings
    assert_equal [@root1, @root2, @root3], @root1.self_and_siblings
    assert_equal [@root_child1, @root_child2], @root_child1.self_and_siblings
    assert_equal [@child1_child], @child1_child.self_and_siblings
    assert_equal [@root_child1, @root_child2], @root_child2.self_and_siblings
    assert_equal [@root1, @root2, @root3], @root2.self_and_siblings
    assert_equal [@root1, @root2, @root3], @root3.self_and_siblings
  end

  def test_root?
    assert @root1.root?
    assert @root2.root?
    assert @root3.root?
    assert !@root_child1.root?
    assert !@root_child2.root?
    assert !@child1_child.root?
  end

  def test_child?
    assert !@root1.child?
    assert !@root2.child?
    assert !@root3.child?
    assert @root_child1.child?
    assert @root_child2.child?
    assert @child1_child.child?
  end

  def test_parent?
    assert @root1.parent?
    assert !@root2.parent?
    assert !@root3.parent?
    assert @root_child1.parent?
    assert !@root_child2.parent?
    assert !@child1_child.parent?
  end

  def test_leaf?
    assert !@root1.leaf?
    assert @root2.leaf?
    assert @root3.leaf?
    assert !@root_child1.leaf?
    assert @root_child2.leaf?
    assert @child1_child.leaf?
  end

  def test_ancestor_of?
    assert @root1.ancestor_of?(@root_child1)
    assert @root1.ancestor_of?(@root_child2)
    assert @root1.ancestor_of?(@child1_child)

    assert !@root_child1.ancestor_of?(@root1)
    assert !@root_child2.ancestor_of?(@root1)
    assert !@child1_child.ancestor_of?(@root1)

    assert !@root1.ancestor_of?(@root1)
    assert !@root1.ancestor_of?(@root2)
    assert !@root1.ancestor_of?(@root3)

    assert @root_child1.ancestor_of?(@child1_child)
    assert !@child1_child.ancestor_of?(@root_child1)
  end

  def test_descendant_of?
    assert !@root1.descendant_of?(@root_child1)
    assert !@root1.descendant_of?(@root_child2)
    assert !@root1.descendant_of?(@child1_child)

    assert @root_child1.descendant_of?(@root1)
    assert @root_child2.descendant_of?(@root1)
    assert @child1_child.descendant_of?(@root1)

    assert !@root1.descendant_of?(@root1)
    assert !@root1.descendant_of?(@root2)
    assert !@root1.descendant_of?(@root3)

    assert !@root_child1.descendant_of?(@child1_child)
    assert @child1_child.descendant_of?(@root_child1)
  end

  def test_child_ids
    assert_equal [@root_child1.id, @root_child2.id], @root1.child_ids
    assert_equal [@child1_child.id], @root_child1.child_ids
  end

  def test_descendants
    assert_equal [@root_child1, @child1_child, @root_child2], @root1.descendants
    assert_equal [@child1_child], @root_child1.descendants
  end

  def test_descendants_dfs
    assert_equal [@root_child1, @child1_child, @root_child2], @root1.descendants_dfs
    assert_equal [@child1_child], @root_child1.descendants_dfs
  end

  def test_descendants_bfs
    assert_equal [@root_child1, @root_child2, @child1_child], @root1.descendants_bfs
    assert_equal [@child1_child], @root_child1.descendants_bfs
  end

  def test_self_and_descendants
    assert_equal [@root1, @root_child1, @child1_child, @root_child2], @root1.self_and_descendants
    assert_equal [@root_child1, @child1_child], @root_child1.self_and_descendants
  end

  def test_self_and_descendants_dfs
    assert_equal [@root1, @root_child1, @child1_child, @root_child2], @root1.self_and_descendants_dfs
    assert_equal [@root_child1, @child1_child], @root_child1.self_and_descendants_dfs
  end

  def test_self_and_descendants_bfs
    assert_equal [@root1, @root_child1, @root_child2, @child1_child], @root1.self_and_descendants_bfs
    assert_equal [@root_child1, @child1_child], @root_child1.self_and_descendants_bfs
  end

  def test_descendant_ids
    assert_equal [@root_child1, @child1_child, @root_child2].map(&:id), @root1.descendant_ids
    assert_equal [@child1_child].map(&:id), @root_child1.descendant_ids
  end

  def test_descendant_ids_dfs
    assert_equal [@root_child1, @child1_child, @root_child2].map(&:id), @root1.descendant_ids_dfs
    assert_equal [@child1_child].map(&:id), @root_child1.descendant_ids_dfs
  end

  def test_descendant_ids_bfs
    assert_equal [@root_child1, @root_child2, @child1_child].map(&:id), @root1.descendant_ids_bfs
    assert_equal [@child1_child].map(&:id), @root_child1.descendant_ids_bfs
  end

  def test_descendants_count
    assert_equal 3, @root1.descendants_count
    assert_equal 0, @root2.descendants_count
    assert_equal 0, @root3.descendants_count
    assert_equal 1, @root_child1.descendants_count
    assert_equal 0, @root_child2.descendants_count
    assert_equal 0, @child1_child.descendants_count
  end
end

class TreeTestWithCounterCache < Test::Unit::TestCase
  def setup
    teardown_db
    setup_db
    @root = TreeMixinWithCounterCache.create!
    @child1 = TreeMixinWithCounterCache.create! :parent_id => @root.id
    @child1_child1 = TreeMixinWithCounterCache.create! :parent_id => @child1.id
    @child2 = TreeMixinWithCounterCache.create! :parent_id => @root.id
  end

  def teardown
    teardown_db
  end

  def test_counter_cache
    assert_equal 2, @root.reload.children_count
    assert_equal 1, @child1.reload.children_count
  end

  def test_update_parents_counter_cache
    @child1_child1.update_attributes(:parent_id => @root.id)
    assert_equal 3, @root.reload.children_count
    assert_equal 0, @child1.reload.children_count
  end

end


class TreeTestWithEagerLoading < Test::Unit::TestCase

  def setup
    teardown_db
    setup_db
    @root1 = TreeMixin.create!
    @root_child1 = TreeMixin.create! :parent_id => @root1.id
    @child1_child = TreeMixin.create! :parent_id => @root_child1.id
    @root_child2 = TreeMixin.create! :parent_id => @root1.id
    @root2 = TreeMixin.create!
    @root3 = TreeMixin.create!

    @rc1 = RecursivelyCascadedTreeMixin.create!
    @rc2 = RecursivelyCascadedTreeMixin.create! :parent_id => @rc1.id
    @rc3 = RecursivelyCascadedTreeMixin.create! :parent_id => @rc2.id
    @rc4 = RecursivelyCascadedTreeMixin.create! :parent_id => @rc3.id
  end

  def teardown
    teardown_db
  end

  def test_eager_association_loading
    roots = TreeMixin.find(:all, :include => :children, :conditions => "mixins.parent_id IS NULL", :order => "mixins.id")
    assert_equal [@root1, @root2, @root3], roots
    assert_no_queries do
      assert_equal 2, roots[0].children.count
      assert_equal 0, roots[1].children.count
      assert_equal 0, roots[2].children.count
    end
  end

  def test_eager_association_loading_with_recursive_cascading_three_levels_has_many
    root_node = RecursivelyCascadedTreeMixin.find(:first, :include => { :children => { :children => :children } }, :order => 'mixins.id')
    assert_equal @rc4, assert_no_queries { root_node.children.first.children.first.children.first }
  end

  def test_eager_association_loading_with_recursive_cascading_three_levels_has_one
    root_node = RecursivelyCascadedTreeMixin.find(:first, :include => { :first_child => { :first_child => :first_child } }, :order => 'mixins.id')
    assert_equal @rc4, assert_no_queries { root_node.first_child.first_child.first_child }
  end

  def test_eager_association_loading_with_recursive_cascading_three_levels_belongs_to
    leaf_node = RecursivelyCascadedTreeMixin.find(:first, :include => { :parent => { :parent => :parent } }, :order => 'mixins.id DESC')
    assert_equal @rc1, assert_no_queries { leaf_node.parent.parent.parent }
  end
end

class TreeTestWithoutOrder < Test::Unit::TestCase

  def setup
    setup_db
    @root1 = TreeMixinWithoutOrder.create!
    @root2 = TreeMixinWithoutOrder.create!
  end

  def teardown
    teardown_db
  end

  def test_root
    assert [@root1, @root2].include?(TreeMixinWithoutOrder.root)
  end

  def test_roots
    assert_equal [], [@root1, @root2] - TreeMixinWithoutOrder.roots
  end
end
