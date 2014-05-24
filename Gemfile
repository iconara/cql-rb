source 'https://rubygems.org/'

gemspec

gem 'rake'
gem 'snappy'
gem 'ione', github: 'iconara/ione', branch: 'ssl_support'

group :development do
  gem 'pry'
  platforms :mri do
    gem 'yard'
    gem 'redcarpet'
  end
  platforms :mri_19 do
    gem 'perftools.rb'
  end
end

group :test do
  gem 'rspec'
  gem 'simplecov'
  gem 'coveralls'
end