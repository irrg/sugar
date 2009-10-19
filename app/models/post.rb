require 'post_parser'

class Post < ActiveRecord::Base

	POSTS_PER_PAGE  = 50

	belongs_to :user, :counter_cache => true
	belongs_to :discussion, :counter_cache => true
	has_many   :discussion_views

	validates_presence_of :body, :user_id, :discussion_id

	validate do |post|
		post.trusted = post.discussion.trusted if post.discussion
		post.edited_at ||= Time.now
	end

	# Automatically update the discussion with last poster info
	after_create do |post|
		post.discussion.update_attributes(:last_poster_id => post.user.id, :last_post_at => post.created_at)
		DiscussionRelationship.define(post.user, post.discussion, :participated => true)
	end

	before_save do |post|
		post.body_html = PostParser.parse(post.body)
	end
	
	define_index do
		indexes body
		indexes user(:username), :as => :username
		has     user_id, discussion_id
		has     created_at, updated_at
		has     trusted
		set_property :delta => :delayed
	end

	class << self

		def find_paginated(options={})
			discussion = options[:discussion]
			Pagination.paginate(
				:total_count => discussion.posts_count,
				:per_page    => options[:limit] || POSTS_PER_PAGE,
				:page        => options[:page] || 1,
				:context     => options[:context] || 0
			) do |pagination|
				Post.find(
					:all,
					:conditions => ['discussion_id = ?', discussion.id],
					:limit      => pagination.limit,
					:offset     => pagination.offset,
					:order      => 'created_at ASC',
					:include    => [:user]
				)
			end
		end

		def search_paginated(options={})
			page  = (options[:page] || 1).to_i
			page = 1 if page < 1
			search_options = {
				:order      => :created_at, 
				:sort_mode  => :desc, 
				:per_page   => POSTS_PER_PAGE,
				:page       => page,
				:include    => [:user, :discussion],
				:match_mode => :extended2
			}
			search_options[:conditions] = {}
			search_options[:conditions][:trusted] = false unless options[:trusted]
			search_options[:conditions][:discussion_id] = options[:discussion_id] if options[:discussion_id]
			posts = Post.search(options[:query], search_options)
			Pagination.apply(posts, Pagination::Paginater.new(:total_count => posts.total_entries, :page => page, :per_page => POSTS_PER_PAGE))
		end
	end

	def me_post?
		@me_post ||= (body.strip =~ /^\/me/ && !(body =~ /\n/) ) ? true : false
	end

	# Get this posts sequence number
	def post_number
		#@post_number ||= ( Post.count_by_sql("SELECT COUNT(*) FROM posts WHERE discussion_id = #{self.discussion.id} AND created_at < '#{self.created_at.to_formatted_s(:db)}'") + 1)
		@post_number ||= (Post.count(:conditions => ['discussion_id = ? AND created_at < ?', self.discussion_id, self.created_at]) + 1)
	end

	def page(options={})
		limit = options[:limit] || POSTS_PER_PAGE
		(post_number.to_f/limit).ceil
	end

	def body_html
		unless body_html?
			self.update_attribute(:body_html, PostParser.parse(self.body.dup))
		end
		self[:body_html]
	end

	def edited?
		return false unless edited_at?
		(((self.edited_at || self.created_at) - self.created_at) > 5.seconds ) ? true : false
	end

	def editable_by?(user)
		(user && (user.admin? || user == self.user)) ? true : false
	end

	def viewable_by?(user)
		(user && !(self.discussion.trusted? && !(user.trusted? || user.admin?))) ? true : false
	end
end
