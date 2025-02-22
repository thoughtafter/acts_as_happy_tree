require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "acts_as_happy_tree"
    gem.summary = %Q{acts_as_happy_tree as a gem}
    gem.description = %Q{acts_as_happy_tree as a gem}
    gem.email = "jim@saturnflyer.com"
    gem.homepage = "http://github.com/saturnflyer/acts_as_happy_tree"
    gem.authors = ["David Heinemeier Hansson",'and others']
    # gem.add_development_dependency "thoughtbot-shoulda"
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: sudo gem install jeweler"
end

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.test_files = FileList['test/*_test.rb']
  test.verbose = true
end

task 'test:ar30' do
  ENV['AR_VERSION'] = '3.0.10'
  Rake::Task["test"].execute
end

task 'test:ar31' do
  ENV['AR_VERSION'] = '3.1.2'
  Rake::Task["test"].execute
end

task 'test:ar32' do
  ENV['AR_VERSION'] = '3.2.1'
  Rake::Task["test"].execute
end

task 'test:all' => ['test:ar32', 'test:ar31', 'test:ar30']

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |test|
    test.libs << 'test'
    test.pattern = 'test/**/*_test.rb'
    test.verbose = true
  end
rescue LoadError
  task :rcov do
    abort "RCov is not available. In order to run rcov, you must: sudo gem install spicycode-rcov"
  end
end

task :test => :check_dependencies

task :default => :test

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  if File.exist?('VERSION')
    version = File.read('VERSION')
  else
    version = ""
  end

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "acts_as_happy_tree #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
