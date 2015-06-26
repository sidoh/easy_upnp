$:.push File.expand_path('../lib', __FILE__)

require "easy_upnp/version"

Gem::Specification.new do |gem|
  gem.name    = 'easy_upnp'
  gem.version = EasyUpnp::VERSION

  gem.summary = "A super easy to use UPnP control point client"

  gem.authors  = ['Christopher Mullins']
  gem.email    = 'chris@sidoh.org'
  gem.homepage = 'http://github.com/sidoh/easy-upnp'

  gem.add_dependency 'rake' 
  gem.add_dependency 'savon', '~> 2.11.1'
  gem.add_dependency 'nori', '~> 2.6.0'
  gem.add_dependency 'nokogiri', '~> 1.6.6.2'

  gem.add_development_dependency('rspec', [">= 2.0.0"])

  ignores  = File.readlines(".gitignore").grep(/\S+/).map(&:chomp)
  dotfiles = %w[.gitignore]

  all_files_without_ignores = Dir["**/*"].reject { |f|
    File.directory?(f) || ignores.any? { |i| File.fnmatch(i, f) }
  }

  gem.files = (all_files_without_ignores + dotfiles).sort

  gem.require_path = "lib" 
end
