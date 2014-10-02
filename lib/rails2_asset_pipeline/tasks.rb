# encoding: UTF-8
require 'rails2_asset_pipeline'
require 'rake/sprocketstask'

namespace :assets do
  load_tasks = lambda do
    namespace :r2ap do
      Rake::SprocketsTask.new do |t|
        t.environment = Rails2AssetPipeline.env
        t.output = "./public/#{Rails2AssetPipeline.prefix}"
        if t.respond_to?(:manifest=) # sprockets 2.8+ ?
          t.manifest = Sprockets::Manifest.new(t.environment.index, "./public/#{Rails2AssetPipeline.prefix}/manifest.json")
        end

        # TODO: whitelist within /vendor/assets/components
        # For Bowser deps, explicitly add the paths we want to precompile (so we don't hit README, extra /src directories, etc)
        # 1) loop over all /vendor/assets/components dirs
        # 2) find bower.json file
        # 3) append all paths from "main" key to our paths list
        bower_logical_paths = []
        Dir.glob("#{Rails.root}/vendor/assets/components/**/{bower.json}").map do |bower_json_path|
          base_path = bower_json_path.gsub('/bower.json', '')
          main_val = JSON.parse(File.read(bower_json_path))["main"]
          # could be a single value or an array, so coerce to array before looping
          [*main_val].each do |relative_path|
            full_path = File.expand_path(relative_path, base_path)
            logical_path = full_path.gsub("#{Rails.root}/vendor/assets/components/", '')
            # Sprockets will look for .scss and .sass dependencies as .css 
            # ex: vendor/assets/components/bootstrap-sass-official/assets/stylesheets/_bootstrap.scss,
            # Sprocket's logical path has _bootstrap.css instead
            logical_path = logical_path.gsub(/\.(scss|sass|less)$/, '.css')
            bower_logical_paths << logical_path
          end
        end
        bower_logical_paths.uniq!
        bower_logical_path_bases = bower_logical_paths.map { |str| str.split('/').first+'/' }.uniq

        whitelisted_bower_logical_paths_found = []
        t.assets = t.environment.each_logical_path.map do |logical_path|
          partial = (logical_path =~ %r{(^|/)_[^/]*.css$})

          # Sprockets integration with Bower is dumb, so all we can do is append our Bower path, and it will
          # recursively pull in all files within the Bower subdirs. So we need a way to filter out any files
          # that aren't whitelisted by the bower.json "main" key. This code does that.
          is_bower_path = bower_logical_path_bases.any? { |str| logical_path.start_with?(str) }
          is_bower_whitelisted = is_bower_path && bower_logical_paths.include?(logical_path)
          whitelisted_bower_logical_paths_found << logical_path if is_bower_whitelisted

          if !partial && !(is_bower_path && !is_bower_whitelisted) && asset = t.environment.find_asset(logical_path)
            asset.pathname.to_s
          end
        end.compact

        # assert that the number of Wower assets that made it
        # through our filter equals the number of whitelisted Bower assets
        if whitelisted_bower_logical_paths_found.size != bower_logical_paths.size
          missing_logical_paths = bower_logical_paths.select { |x| !whitelisted_bower_logical_paths_found.include?(x) }
          raise "Expected #{bower_logical_paths.size} Bower deps, but found #{whitelisted_bower_logical_paths_found.size}. Missing:\n#{missing_logical_paths.join("\n")}"
        end

        t.log_level = Logger::ERROR
        t.keep = 2
      end
    end
  end

  task :config do
    initializer = Rails.root.join("config/initializers/rails2_asset_pipeline.rb")
    load initializer if File.exist?(initializer)
  end

  desc "Compile all the assets"
  task :precompile => "assets:config" do
    load_tasks.call
    Rake::Task["r2ap:assets"].invoke
  end

  desc "Remove compiled assets"
  task :clean => "assets:config" do
    load_tasks.call
    Rake::Task["r2ap:clobber"].invoke
  end

  desc "Remove old assets"
  task :remove_old => "assets:config" do
    load_tasks.call
    Rake::Task["r2ap:clean"].invoke
  end

  desc "converts project from jammit based assets.yml"
  task :convert_jammit do
    require 'rails2_asset_pipeline/jammit_converter'
    Rails2AssetPipeline::JammitConverter.convert
  end
end
