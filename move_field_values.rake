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

desc 'Fix a migration by moving data from one field to another'

# require 'active_record'
# require 'iconv' if RUBY_VERSION < '1.9'
# require 'pp'

namespace :redmine do
  task :move_field_values => :environment do

    module MoveFieldValues

      def self.print_milestone(issue)
        # print "Milestone": the field exists but is value can be null
        if issue.fixed_version.nil? 
          puts "        Milestone:  - " 
        else 
          puts "        Milestone: #{issue.fixed_version.id} - #{issue.fixed_version.name}"
        end            
      end

      def self.print_custom_field(issue, field)
        # find custom field in this issue (the field may not exist)
        issue_custom_field = issue.custom_field_values.select{ |item| item.custom_field.id == field.id }.first
        puts "          #{issue_custom_field.custom_field.name}: #{issue_custom_field.value} - #{Version.find_by_id(issue_custom_field.value)}" unless issue_custom_field.nil?
      end

      def self.mass_update()
        puts
        puts "Mass updating records"

        version_field = IssueCustomField.find_by_name("Version")
        #puts "Version_field: #{version_field.id}"
        
        # Find all issues for specific projects
        for project_id in [72, 73, 74, 75, 77] #[82,83]
          puts "- Procesing project: #{project_id} - #{Project.find_by_id(project_id).name}"

          # Retrieve all issues
          for issue in Issue.find(:all, :conditions => {:project_id => project_id})
            puts "  - Procesing issue: #{issue}" 
            
            print_milestone(issue)
            print_custom_field(issue, version_field)
           
            # find "Version" custom field in this issue
            issue_custom_field = issue.custom_field_values.select{ |a| a.custom_field.id == version_field.id }.first

            # copy the milestone field value to the custom "version" field
            if issue_custom_field.nil?
              puts "WARNING: custom field '#{version_field.name}' not found in project '#{project_id} - #{Project.find_by_id(project_id).name}'"
            else
              #issue.fixed_version, issue_custom_field.value = Version.find_by_id(issue_custom_field.value), issue.fixed_version.nil??nil:issue.fixed_version.id
              issue.fixed_version, issue_custom_field.value = nil, issue.fixed_version.nil??nil:issue.fixed_version.id

              # Save issue
              issue.save_custom_field_values
              issue.save!
            end

            puts "        ------------"
            print_milestone(issue)
            print_custom_field(issue, version_field)
            
          end #for issue
          
        end #for project
      end #def



      puts
      puts "REDMINE MASS UPDATE (for moving field values)"
      puts
      puts "WARNING: Your Redmine data could be corrupted during this process."
      print "Are you sure you want to continue ? [y/N] "
      break unless STDIN.gets.match(/^y$/i)


      # Turn off email notifications
      Setting.notified_events = []

      # Make sure no before and after save callbacks are called on Issues since this
      # prevents the created_on und updated_on dates from being set properly
      Issue.reset_callbacks :save
      
      MoveFieldValues.mass_update
    end
  end
end