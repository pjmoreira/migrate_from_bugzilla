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

desc 'Bugzilla migration fix script (ignored markup -- need escape)'

require 'active_record'
require 'iconv' if RUBY_VERSION < '1.9'
require 'pp'

namespace :redmine do
  task :fix_bugzilla_migration => :environment do

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

    register_for_assigned_pk([Issue])


    module BugzillaMigrationFix

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





      def self.fix_issues()
        puts
        print "Fixing migrated issues"

        # Issue.destroy_all
        @issue_map = {}

        BugzillaBug.find(:all, :order => "bug_id ASC").each  do |bug|

          description = bug.descriptions.first.text.to_s

          issue = Issue.find(bug.bug_id)
          issue.description = CGI.escapeHTML(description || bug.short_desc)

          issue.save!

          bug.descriptions.order('bug_when asc').each do |description|

            journal = Journal.find(:first, :conditions => {journalized_id: issue.id, created_on: description.bug_when})

            next if journal.nil?
            next if description === bug.descriptions.first
            next if description.text.nil?

            journal.notes = CGI.escapeHTML(description.text)

            print '.'
            journal.save!

          end

          print '#'
          $stdout.flush
        end
      end




      puts
      puts "BUGZILLA MIGRATION FIX (for dissapeared Markup)"
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

      BugzillaMigrationFix.establish_connection db_params
      BugzillaMigrationFix.fix_issues
    end
  end
end