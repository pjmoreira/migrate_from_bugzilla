# redMine - project management software
# Copyright (C) 2006-2007  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# Bugzilla migration by Arjen Roodselaar, Lindix bv
#

desc 'Bugzilla migration script'

require 'active_record'
require 'iconv' if RUBY_VERSION < '1.9'
require 'pp'

namespace :redmine do
  task :migrate_from_bugzilla => :environment do

    module AssignablePk
      attr_accessor :pk
      def set_pk
        self.id = self.pk unless self.pk.nil?
      end
    end

    def self.register_for_assigned_pk(klasses)
      klasses.each do |klass|
        klass.send(:include, AssignablePk)
        klass.send(:before_create, :set_pk)
      end
    end

    register_for_assigned_pk([User, Project, Issue, IssueCategory, Attachment, Version])

    module BugzillaMigrate


      # danielfernandez - 20140520 - Use status already present in Redmine
      new_status = IssueStatus.find_by_name!('New')
      accepted_status = IssueStatus.find_by_name!('Accepted')
      inprogress_status = IssueStatus.find_by_name!('In Progress')
      developed_status = IssueStatus.find_by_name!('Developed')
      suspended_status = IssueStatus.find_by_name!('Suspended')
      completed_status = IssueStatus.find_by_name!('Completed')
      declined_status = IssueStatus.find_by_name!('Rejected') # Visual name: 'Declined'
      abandoned_status = IssueStatus.find_by_name!('Abandoned')
      invalid_status = IssueStatus.find_by_name!('Invalid')
      reopened_status = IssueStatus.find_by_name!('New (reopened)')


      # danielfernandez: reorganize statuses
      # IssueStatus.delete_all

      # new_status = IssueStatus.new
      # new_status.id = 1
      # new_status.name = 'New'
      # new_status.is_closed = false
      # new_status.is_default = true
      # new_status.position = 1
      # new_status.save

      # accepted_status = IssueStatus.new
      # accepted_status.id = 2
      # accepted_status.name = 'Accepted'
      # accepted_status.is_closed = false
      # accepted_status.is_default = false
      # accepted_status.position = 2
      # accepted_status.save

      # inprogress_status = IssueStatus.new
      # inprogress_status.id = 3
      # inprogress_status.name = 'In Progress'
      # inprogress_status.is_closed = false
      # inprogress_status.is_default = false
      # inprogress_status.position = 3
      # inprogress_status.save

      # developed_status = IssueStatus.new
      # developed_status.id = 4
      # developed_status.name = 'Developed'
      # developed_status.is_closed = false
      # developed_status.is_default = false
      # developed_status.position = 4
      # developed_status.save

      # suspended_status = IssueStatus.new
      # suspended_status.id = 5
      # suspended_status.name = 'Suspended'
      # suspended_status.is_closed = false
      # suspended_status.is_default = false
      # suspended_status.position = 5
      # suspended_status.save

      # completed_status = IssueStatus.new
      # completed_status.id = 6
      # completed_status.name = 'Completed'
      # completed_status.is_closed = true
      # completed_status.is_default = false
      # completed_status.position = 6
      # completed_status.save

      # declined_status = IssueStatus.new
      # declined_status.id = 7
      # declined_status.name = 'Declined'
      # declined_status.is_closed = true
      # declined_status.is_default = false
      # declined_status.position = 7
      # declined_status.save

      # abandoned_status = IssueStatus.new
      # abandoned_status.id = 8
      # abandoned_status.name = 'Abandoned'
      # abandoned_status.is_closed = true
      # abandoned_status.is_default = false
      # abandoned_status.position = 8
      # abandoned_status.save

      # invalid_status = IssueStatus.new
      # invalid_status.id = 9
      # invalid_status.name = 'Invalid'
      # invalid_status.is_closed = true
      # invalid_status.is_default = false
      # invalid_status.position = 9
      # invalid_status.save

      # danielfernandez: 20140520 - Added 'New (reopened)' status
      # reopened_status = IssueStatus.new
      # reopened_status.id = 10
      # reopened_status.name = 'New (reopened)'
      # reopened_status.is_closed = false
      # reopened_status.is_default = false
      # reopened_status.position = 10
      # reopened_status.save

      DEFAULT_STATUS = IssueStatus.default


      # danielfernandez: adapted status mapping, first map by resolution should be attempted, then by status
      RESOLUTION_MAPPING = {
        "DUPLICATE"  => invalid_status,
        "FIXED"      => completed_status,
        "INVALID"    => invalid_status,
        "LATER"      => suspended_status,
        "REMIND"     => suspended_status,
        "WONTFIX"    => declined_status,
        "WORKSFORME" => invalid_status
      }
      STATUS_MAPPING = {
        "UNCONFIRMED" => new_status,
        "NEW"         => new_status,
        "VERIFIED"    => accepted_status,
        "ASSIGNED"    => inprogress_status,
        "REOPENED"    => reopened_status,
        "RESOLVED"    => completed_status,
        "CLOSED"      => completed_status
      }



      # danielfernandez - 20140520 - Use priorities already present in Redmine
      blocking_priority = IssuePriority.find_by_name!('Urgent')  # Display name 'Blocking'
      major_priority = IssuePriority.find_by_name!('High')       # Display name 'Major'
      normal_priority = IssuePriority.find_by_name!('Normal')
      minor_priority = IssuePriority.find_by_name!('Low')        # Display name 'Minor'



      # danielfernandez: reorganize priorities
      # IssuePriority.delete_all

      # blocking_priority = IssuePriority.new
      # blocking_priority.name = 'Blocking'
      # blocking_priority.position = 4
      # blocking_priority.is_default = false
      # blocking_priority.position_name = 'highest'
      # blocking_priority.save

      # major_priority = IssuePriority.new
      # major_priority.name = 'Major'
      # major_priority.position = 3
      # major_priority.is_default = false
      # major_priority.position_name = 'high2'
      # major_priority.save

      # normal_priority = IssuePriority.new
      # normal_priority.name = 'Normal'
      # normal_priority.position = 2
      # normal_priority.is_default = true
      # normal_priority.position_name = 'default'
      # normal_priority.save

      # minor_priority = IssuePriority.new
      # minor_priority.name = 'Minor'
      # minor_priority.position = 1
      # minor_priority.is_default = false
      # minor_priority.position_name = 'lowest'
      # minor_priority.save
      
      DEFAULT_PRIORITY = IssuePriority.default

      PRIORITY_MAPPING = {
        "P5" => minor_priority,
        "P4" => normal_priority,
        "P3" => normal_priority,
        "P2" => major_priority,
        "P1" => blocking_priority
      }



      # danielfernandez - 20140520 - Use trackers already present in Redmine
      # The visual names are 'Problem', 'Feature', 'Question' and 'Task', but
      # Redmine keeps in database their original names, which were
      # 'Bug', 'Feature', 'Support' and 'Task'
      problem_tracker = Tracker.find_by_name!('Bug')
      feature_tracker = Tracker.find_by_name!('Feature')
      question_tracker = Tracker.find_by_name!('Support')
      task_tracker = Tracker.find_by_name!('Task')



      # danielfernandez: reorganize trackers
      # Tracker.delete_all

      # problem_tracker = Tracker.new
      # problem_tracker.name = 'Problem'
      # problem_tracker.is_in_chlog = true
      # problem_tracker.position = 1
      # problem_tracker.is_in_roadmap = false
      # problem_tracker.fields_bits = 0
      # problem_tracker.save

      # feature_tracker = Tracker.new
      # feature_tracker.name = 'Feature'
      # feature_tracker.is_in_chlog = true
      # feature_tracker.position = 2
      # feature_tracker.is_in_roadmap = true
      # feature_tracker.fields_bits = 0
      # feature_tracker.save

      # question_tracker = Tracker.new
      # question_tracker.name = 'Question'
      # question_tracker.is_in_chlog = false
      # question_tracker.position = 3
      # question_tracker.is_in_roadmap = false
      # question_tracker.fields_bits = 0
      # question_tracker.save

      # task_tracker = Tracker.new
      # task_tracker.name = 'Task'
      # task_tracker.is_in_chlog = true
      # task_tracker.position = 4
      # task_tracker.is_in_roadmap = false
      # task_tracker.fields_bits = 0
      # task_tracker.save

      DEFAULT_TRACKER = problem_tracker

      TRACKER_MAPPING = {
        "critical" => problem_tracker,
        "blocker" => problem_tracker,
        "major" => problem_tracker,
        "normal" => problem_tracker,
        "minor" => problem_tracker,
        "trivial" => problem_tracker,
        "enhancement" => feature_tracker
      }


      # danielfernandez - 20140520 - Retrieve roles from DB by name instead of position
      reporter_role = Role.find_by_name!('Reporter')      # Display name 'User'
      developer_role = Role.find_by_name!('Developer')    # Display name 'Member'
      manager_role = Role.find_by_name!('Manager')        # Display name 'Master'
      DEFAULT_ROLE = reporter_role
      MANAGER_ROLE = manager_role

      CUSTOM_FIELD_TYPE_MAPPING = {
        0 => 'string', # String
        1 => 'int',    # Numeric
        2 => 'int',    # Float
        3 => 'list',   # Enumeration
        4 => 'string', # Email
        5 => 'bool',   # Checkbox
        6 => 'list',   # List
        7 => 'list',   # Multiselection list
        8 => 'date',   # Date
      }

      RELATION_TYPE_MAPPING = {
        0 => IssueRelation::TYPE_DUPLICATES, # duplicate of
        1 => IssueRelation::TYPE_RELATES,    # related to
        2 => IssueRelation::TYPE_RELATES,    # parent of
        3 => IssueRelation::TYPE_RELATES,    # child of
        4 => IssueRelation::TYPE_DUPLICATES  # has duplicate
      }

      BUGZILLA_ID_FIELDNAME = "Bugzilla-Id"

      class BugzillaProfile < ActiveRecord::Base
        set_table_name :profiles
        set_primary_key :userid

        has_and_belongs_to_many :groups,
          :class_name => "BugzillaGroup",
          :join_table => :user_group_map,
          :foreign_key => :user_id,
          :association_foreign_key => :group_id

        def login
          login_name[0..29].gsub(/[^a-zA-Z0-9_\-@\.]/, '-')
        end

        def email
          if login_name.match(/^.*@.*$/i)
            login_name
          else
            "#{login_name}@foo.bar"
          end
        end

        def lastname
          s = read_attribute(:realname)
          return 'unknown' if(s.blank?)
          return s.split(/[ ,]+/, 2)[-1]
        end

        def firstname
          s = read_attribute(:realname)
          return 'unknown' if(s.blank?)
          return s.split(/[ ,]+/, 2).first
        end
      end

      class BugzillaGroup < ActiveRecord::Base
        set_table_name :groups

        has_and_belongs_to_many :profiles,
          :class_name => "BugzillaProfile",
          :join_table => :user_group_map,
          :foreign_key => :group_id,
          :association_foreign_key => :user_id
      end

      class BugzillaProduct < ActiveRecord::Base
        set_table_name :products

        has_many :components, :class_name => "BugzillaComponent", :foreign_key => :product_id
        has_many :versions, :class_name => "BugzillaVersion", :foreign_key => :product_id
        has_many :bugs, :class_name => "BugzillaBug", :foreign_key => :product_id
      end

      class BugzillaComponent < ActiveRecord::Base
        set_table_name :components
      end

      class BugzillaCC < ActiveRecord::Base
        set_table_name :cc
      end

      class BugzillaVersion < ActiveRecord::Base
        set_table_name :versions
      end

      class BugzillaBug < ActiveRecord::Base
        set_table_name :bugs
        set_primary_key :bug_id

        belongs_to :product, :class_name => "BugzillaProduct", :foreign_key => :product_id
        has_many :descriptions, :class_name => "BugzillaDescription", :foreign_key => :bug_id
        has_many :attachments, :class_name => "BugzillaAttachment", :foreign_key => :bug_id
      end

      class BugzillaDependency < ActiveRecord::Base
        set_table_name :dependencies
      end

      class BugzillaDuplicate < ActiveRecord::Base
        set_table_name :duplicates
      end

      class BugzillaDescription < ActiveRecord::Base
        set_table_name :longdescs
        set_inheritance_column :bongo
        belongs_to :bug, :class_name => "BugzillaBug", :foreign_key => :bug_id

        def eql(desc)
          self.bug_when == desc.bug_when
        end

        def === desc
          self.eql(desc)
        end

        def text
          if self.thetext.blank?
            return nil
          else
            self.thetext
          end
        end
      end

      class BugzillaAttachment < ActiveRecord::Base
        set_table_name :attachments
        set_primary_key :attach_id

        has_one :attach_data, :class_name => 'BugzillaAttachData', :foreign_key => :id


        def size
          return 0 if self.attach_data.nil?
          return self.attach_data.thedata.size
        end

        def original_filename
          return self.filename
        end

        def content_type
          self.mimetype
        end

        def read(*args)
          if @read_finished
            nil
          else
            @read_finished = true
            return nil if self.attach_data.nil?
            return self.attach_data.thedata
          end
        end
      end

      class BugzillaAttachData < ActiveRecord::Base
        set_table_name :attach_data
      end


      def self.establish_connection(params)
        constants.each do |const|
          klass = const_get(const)
          next unless klass.respond_to? 'establish_connection'
          klass.establish_connection params
        end
      end

      def self.map_user(userid)
         return @user_map[userid]
      end

      def self.migrate_users
        puts
        print "Migrating profiles\n"
        $stdout.flush

        # bugzilla userid => redmine user pk.  Use email address
        # as the matching mechanism.  If profile exists in redmine,
        # leave it untouched, otherwise create a new user and copy
        # the profile data from bugzilla

        @user_map = {}
        BugzillaProfile.all(:order => :userid).each do |profile|
          profile_email = profile.email
          profile_email.strip!
          existing_redmine_user = User.find_by_mail(profile_email)

          if existing_redmine_user

            @user_map[profile.userid] = existing_redmine_user.id

          else

            # danielfernandez - 20140520 - Create user with LDAP auth
            puts "Creating non-existing user: #{profile.login}"
            user = User.new
            user.login = profile.login
            user.password = "inactive"
            user.firstname = profile.firstname
            user.lastname = profile.lastname
            user.auth_source_id = 1
            user.mail = profile.email
            user.mail.strip!
            user.status = User::STATUS_LOCKED if !profile.disabledtext.empty?
            user.admin = true if profile.groups.include?(BugzillaGroup.find_by_name("admin"))
            unless user.save then
              puts "FAILURE saving user"
              puts "user: #{user.inspect}"
              puts "bugzilla profile: #{profile.inspect}"
              validation_errors = user.errors.collect {|e| e.to_s }.join(", ")
              puts "validation errors: #{validation_errors}"
            end
            @user_map[profile.userid] = user.id

            # danielfernandez - 20140520 - Commented out in favour of new method
            # create the new user with its own fresh pk
            # and make an entry in the mapping
            # user = User.new
            # user.login = profile.login
            # user.password = "bugzilla"
            # user.firstname = profile.firstname
            # user.lastname = profile.lastname
            # user.mail = profile.email
            # user.mail.strip!
            # user.status = User::STATUS_LOCKED if !profile.disabledtext.empty?
            # user.admin = true if profile.groups.include?(BugzillaGroup.find_by_name("admin"))
            # unless user.save then
            #   puts "FAILURE saving user"
            #   puts "user: #{user.inspect}"
            #   puts "bugzilla profile: #{profile.inspect}"
            #   validation_errors = user.errors.collect {|e| e.to_s }.join(", ")
            #   puts "validation errors: #{validation_errors}"
            # end
            # @user_map[profile.userid] = user.id

          end
          print '.'
        end
        $stdout.flush
      end

      def self.migrate_products
        puts
        print "Migrating products"
        $stdout.flush

        @project_map = {}
        @category_map = {}

        BugzillaProduct.find_each do |product|
          project = Project.new
          project.name = product.name
          project.description = product.description
          project.identifier = "#{product.name.downcase.gsub(/[^a-z0-9]+/, '-')[0..10]}-#{product.id}"
          project.is_public = false
          project.save!

          @project_map[product.id] = project.id

          print '.'
          $stdout.flush

          product.versions.each do |version|
            Version.create(:name => version.value, :project => project)
          end

          # Components
          product.components.each do |component|
            # assume all components get a new category

            category = IssueCategory.new(:name => component.name[0,30])
            #category.pk = component.id
            category.project = project
            uid = map_user(component.initialowner)
            category.assigned_to = User.first(:conditions => {:id => uid })
            category.save
            @category_map[component.id] = category.id
          end
        end
      end

      def self.migrate_products_users_relationship()
        puts
        print "Migrating relationship product/profile"
        BugzillaProfile.all.each do |profile|
            profile.groups.where('isbuggroup = 1').group('name').each do |group|
                #puts "#{profile.login_name} ==> #{group.name}"
                project = Project.find_by_name(group.name)
                user = User.find(map_user(profile.id))
                membership = Member.new(
                   :user => user,
                   :project => project
                )
                membership.roles << DEFAULT_ROLE unless user.admin
                membership.roles << MANAGER_ROLE if user.admin
                membership.save
                print '.'
            end
        end
      end

      def self.migrate_issues()
        puts
        print "Migrating issues"

        # Issue.destroy_all
        @issue_map = {}

        custom_field = IssueCustomField.find_by_name(BUGZILLA_ID_FIELDNAME)

        BugzillaBug.find(:all, :order => "bug_id ASC").each  do |bug|
          #puts "Processing bugzilla bug #{bug.bug_id}"
          description = bug.descriptions.first.text.to_s

          subject = bug.short_desc
          subject = "No description" if subject.empty?

          issue = Issue.new(
            :project_id => @project_map[bug.product_id],
            :subject => subject,
            :description => description || bug.short_desc,
            :author_id => map_user(bug.reporter),
            :priority => PRIORITY_MAPPING[bug.priority] || DEFAULT_PRIORITY,
            # danielfernandez: Modified to perform first a by-resolution mapping
            :status => RESOLUTION_MAPPING[bug.resolution] || STATUS_MAPPING[bug.bug_status] || DEFAULT_STATUS,
            :start_date => bug.creation_ts,
            :created_on => bug.creation_ts,
            :updated_on => bug.delta_ts
          ) { |t| t.id = bug.bug_id }

          # danielfernandez: Modified in order to allow issues to be migrated into other trackers than the "bugs" one
          issue.tracker = TRACKER_MAPPING[bug.bug_severity] || DEFAULT_TRACKER
          # issue.category_id = @category_map[bug.component_id]

          issue.category_id =  @category_map[bug.component_id] unless bug.component_id.blank?
          issue.assigned_to_id = map_user(bug.assigned_to) unless bug.assigned_to.blank?
          version = Version.first(:conditions => {:project_id => @project_map[bug.product_id], :name => bug.version })
          issue.fixed_version = version

          issue.due_date = bug.deadline if bug.deadline && bug.deadline > bug.creation_ts
          issue.estimated_hours = bug.estimated_time if bug.estimated_time && bug.estimated_time > 0

          issue.save!

          #Because time log we need to set the root_id field
          issue.root_id = issue.id
          issue.save!

          #puts "Redmine issue number is #{issue.id}"
          @issue_map[bug.bug_id] = issue.id

          # Create watchers
          BugzillaCC.find_all_by_bug_id(bug.bug_id).each do |cc|
            Watcher.create(:watchable_type => 'Issue',
                           :watchable_id => issue.id,
                           :user_id => map_user(cc.who))
          end

          bug.descriptions.order('bug_when asc').each do |description|
            # the first comment is already added to the description field of the bug
            next if description === bug.descriptions.first
            journal = Journal.new(
              :journalized => issue,
              :user_id => map_user(description.who),
              :notes => description.text,
              :created_on => description.bug_when
            )
            journal.save!
          end

          # Add a journal entry to capture the original bugzilla bug ID
          journal = Journal.new(
            :journalized => issue,
            :user_id => 1,
            :notes => "Original Bugzilla ID was #{bug.id}"
          )
          journal.save!

          # Additionally save the original bugzilla bug ID as custom field value.
          issue.custom_field_values = { custom_field.id => "#{bug.id}" }
          issue.save_custom_field_values

          print '.'
          $stdout.flush
        end
      end

      def self.migrate_issues_time()
        puts
        puts "Migrating issues time"

        BugzillaDescription.where('work_time > 0').order('bug_id asc').order('bug_when asc').each do |desc|
            #puts "bug_id=#{desc.bug_id}, product_id=#{desc.bug.product_id}, who=#{desc.who}, work_time=#{desc.work_time}"
            #puts "issue_id=#{@issue_map[desc.bug_id]}, project_id=#{@project_map[desc.bug.product_id]}, user_id=#{map_user(desc.who)}"
            project = Project.find(@project_map[desc.bug.product_id])
            issue = Issue.find(@issue_map[desc.bug_id])
            user = User.find(map_user(desc.who))
            time_entry = TimeEntry.new(
                          :project => project,
                          :issue => issue,
                          :user => user,
                          :spent_on => desc.bug_when,
                          :hours => desc.work_time,
                          :activity_id => 9,
                          :created_on => desc.bug_when,
                          :updated_on => desc.bug_when)
            #time_entry.safe_attributes = 'project_id', 'issue_id', 'user_id', 'spent_on', 'hours', 'created_on', 'updated_on', 'activity_id'
            time_entry.save!
            print '.'
        end
      end

      def self.migrate_attachments()
        puts
        print "Migrating attachments"
        BugzillaAttachment.find_each() do |attachment|
          next if attachment.attach_data.nil?
          a = Attachment.new :created_on => attachment.creation_ts
          a.file = attachment
          a.author = User.find(map_user(attachment.submitter_id)) || User.first
          a.container = Issue.find(@issue_map[attachment.bug_id])
          a.save

          print '.'
          $stdout.flush
        end
      end

      def self.migrate_issue_relations()
        puts
        print "Migrating issue relations"
        BugzillaDependency.find_by_sql("select blocked, dependson from dependencies").each do |dep|
          rel = IssueRelation.new
          rel.issue_to_id = @issue_map[dep.blocked]
          rel.issue_from_id = @issue_map[dep.dependson]
          rel.relation_type = "blocks"
          rel.save
          print '.'
          $stdout.flush
        end

        BugzillaDuplicate.find_by_sql("select dupe_of, dupe from duplicates").each do |dup|
          rel = IssueRelation.new
          rel.issue_from_id = @issue_map[dup.dupe_of]
          rel.issue_to_id = @issue_map[dup.dupe]
          rel.relation_type = "duplicates"
          rel.save
          print '.'
          $stdout.flush
        end
      end

      def self.create_custom_bug_id_field
         custom = IssueCustomField.find_by_name(BUGZILLA_ID_FIELDNAME)
         return if custom
         custom = IssueCustomField.new({:regexp => "",
                                        :position => 1,
                                        :name => BUGZILLA_ID_FIELDNAME,
                                        :is_required => false,
                                        :min_length => 0,
                                        :default_value => "",
                                        :searchable =>true,
                                        :is_for_all => true,
                                        :max_length => 0,
                                        :is_filter => true,
                                        :editable => true,
                                        :field_format => "string" })
         custom.save!

         Tracker.all.each do |t|
           t.custom_fields << custom
           t.save!
         end
      end

      puts
      puts "WARNING: Your Redmine data could be corrupted during this process."
      print "Are you sure you want to continue ? [y/N] "
      break unless STDIN.gets.match(/^y$/i)

      # Default Bugzilla database settings
      db_params = {:adapter => 'mysql2',
        :database => 'bugs',
        :host => 'localhost',
        :port => 3306,
        :username => '',
        :password => '',
        :encoding => 'utf8'}

      puts
      puts "Please enter settings for your Bugzilla database"
      [:adapter, :host, :port, :database, :username, :password].each do |param|
          print "#{param} [#{db_params[param]}]: "
          value = STDIN.gets.chomp!
          value = value.to_i if param == :port
          db_params[param] = value unless value.blank?
      end

      # Make sure bugs can refer bugs in other projects
      Setting.cross_project_issue_relations = 1 if Setting.respond_to? 'cross_project_issue_relations'

      # Turn off email notifications
      Setting.notified_events = []

      # Make sure no before and after save callbacks are called on Issues since this
      # prevents the created_on und updated_on dates from being set properly
      Issue.reset_callbacks :save

      BugzillaMigrate.establish_connection db_params
      BugzillaMigrate.create_custom_bug_id_field
      BugzillaMigrate.migrate_users
      BugzillaMigrate.migrate_products
      BugzillaMigrate.migrate_products_users_relationship
      BugzillaMigrate.migrate_issues
      BugzillaMigrate.migrate_issues_time
      BugzillaMigrate.migrate_attachments
      BugzillaMigrate.migrate_issue_relations
    end
  end
end
