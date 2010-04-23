require 'digest/sha2'

module Pseudocephalopod
  module Caching
    
    class << self
      attr_accessor :cache_expires_in
    end
    
    # Cache for 10 minutes by default.
    self.cache_expires_in = 600
   
    def self.included(parent)
      parent.extend ClassMethods
      
      parent.class_eval do
        include InstanceMethods
        extend  ClassMethods
        after_save :globally_cache_slug
      end
    end
   
    module InstanceMethods
      def globally_cache_slug
        return unless send(:"#{self.cached_slug_column}_changed?")
        value = self.to_slug
        self.class.cache_slug_lookup!(value, self) if value.present?
        unless store_slug_history
          value = send(:"#{self.cached_slug_column}_was")
          self.class.cache_slug_lookup!(value, nil)
        end
      end
      
      def remove_slug_history!
        previous_slugs.each { |s| self.class.cache_slug_lookup!(s, nil) }
        super
      end
      
    end
   
    module ClassMethods
      
      def find_using_slug(slug, options = {})
        # First, attempt to load an id and then record from the cache.
        if (cached_id = lookup_cached_id_from_slug(slug)).present?
          return find(cached_id, options).tap { |r| r.found_via_slug = slug }
        end
        # Otherwise, fallback to the normal approach.
        super.tap do |record|
          cache_slug_lookup!(slug, record) if record.present?
        end
      end
      
      def slug_cache_key(slug)
        [Pseudocephalopod.cache_key_prefix, slug_scope_key(Digest::SHA256.hexdigest(slug.to_s.strip))].compact.join("/")
      end
      
      def has_cache_for_slug?(slug)
        lookup_cached_id_from_slug(slug).present?
      end
      
      def cache_slug_lookup!(slug, record)
        return if Pseudocephalopod.cache.blank?
        cache = Pseudocephalopod.cache
        key   = slug_cache_key(slug)
        # Set an expires in option for caching.
        caching_options = Hash.new.tap do |hash|
          expiry = Pseudocephalopod::Caching.cache_expires_in
          hash[:expires_in] = expiry.to_i if expiry.present?
        end
        record.nil? ? cache.delete(key) : cache.write(key, record.id, hash)
      end
      
      protected
      
      def lookup_cached_id_from_slug(slug)
        Pseudocephalopod.cache && Pseudocephalopod.cache.read(slug_cache_key(slug))
      end
      
    end
    
  end
end