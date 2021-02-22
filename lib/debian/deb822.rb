# frozen_string_literal: true
#
# Copyright (C) 2015-2016 Harald Sitter <sitter@kde.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) version 3, or any
# later version accepted by the membership of KDE e.V. (or its
# successor approved by the membership of KDE e.V.), which shall
# act as a proxy defined in Section 6 of version 3 of the license.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

require 'insensitive_hash/minimal'

require_relative 'relationship'

module Debian
  # Deb822 specification parser.
  class Deb822
    def parse_relationships(line)
      ret = []
      line.split(',').each do |string|
        rel_array = []
        string.split('|').each do |entry|
          r = Relationship.new(entry)
          next unless r.name # Invalid name, ignore this bugger.

          rel_array << r
        end
        ret << rel_array unless rel_array.empty?
      end
      ret
    end

    # Disable metrics violations here. This method is super complicated, super
    # deep and super hard to read. Splitting it does not improve any of this
    # though. Eventually it may be nice to have a more OOP Parser where the
    # parsable types are own Objects, again, I am not sure that will improve
    # readability in any form or fashion.
    # rubocop:disable Metrcis/MethodLength, Metrics/BlockNesting,
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity,
    # rubocop:disable Metrics/PerceivedComplexity
    def parse_paragraph(lines, fields = {})
      mandatory_fields = fields[:mandatory] || []
      multiline_fields = fields[:multiline] || []
      foldable_fields = fields[:foldable] || []
      relationship_fields = fields[:relationship] || []

      current_header = nil
      data = InsensitiveHash.new

      while (line = lines.shift) && line && !line.strip.empty?
        next if line.start_with?('#') # Comment

        # Make sure the line is well-formed. If a paragraph is at EOF but
        # doesn't have a terminal \n it'd trip our parsing expectations here.
        line = line + "\n" unless line.end_with?("\n")

        header_match = line.match(/^(\S+):(.*\n?)$/)
        # Only match a single space for foldables, in the case of multiline
        # we want to preserve all leading whitespaces except for the
        # format-enforced whitespace.
        fold_match = line.match(/^\s(.+\n)$/)

        unless header_match.nil?
          # 0 = full match
          # 1 = key match
          # 2 = value match
          key = header_match[1].lstrip
          value = header_match[2].lstrip
          current_header = key
          if foldable_fields.include?(key.downcase)
            # We do not care about whitespaces for folds, so strip everything.
            if relationship_fields.include?(key.downcase)
              value = parse_relationships(value)
            else
              # FIXME: this is utterly wrong.
              # A foldable field simply can be folded. In addition to that
              # Binary and Uploaders are comma separated. That does not mean
              # every foldable field is comma seprated! e.g. Dgit is a hash
              # followed by a whitespace! (why is beyond anyones fucking
              # apprehension). If the debian policy was any more of a cluster
              # fuck it'd be on pornhub.
              value = value.split(',').collect(&:strip).select { |x| !x.empty? }
            end
          elsif multiline_fields.include?(key.downcase)
            # For multiline we want to preserve right hand side whitespaces.
            value
          else
            value.strip!
          end
          data[key] = value
          next
        end

        unless fold_match.nil?
          # Folding value encountered -> append to header.
          # [0] = full match
          # [1] = value match
          value = fold_match[1]

          # Fold matches can either be proper RFC 5322 folds or
          # multiline continuations, latter wants to preserve
          # newlines and so forth.
          # The type is entirely dependent on what the header field is.
          if foldable_fields.include?(current_header.downcase)
            value = value.lstrip
            # We do not care about whitespaces for folds, so strip everything.
            if relationship_fields.include?(current_header.downcase)
              value = parse_relationships(value)
            else
              value = value.split(',').collect(&:strip).select { |x| !x.empty? }
            end
            data[current_header] += value
          elsif multiline_fields.include?(current_header.downcase)
            # For multiline fields we only want to strip the leading space, all
            # other lefthand side spaces are to be preserved!
            # This strip is implictly done by our regex. No extra work!
            # We'll also  want to preserve right hand side whitespaces.
            data[current_header] << value
          else
            raise "A field is folding that is not allowed to #{current_header}"
          end

          next
        end

        # TODO: user defined fields

        raise "Paragraph parsing ran into an unknown line: '#{line}'"
      end

      # If the entire stanza was commented out we can end up with no data, it
      # is very sad.
      return nil if data.empty?

      # Special cleanup code for multiline fields.
      data.each do |field, _value|
        # For multiline field we've preserved its right hand side whitespaces
        # (i.e. trailing ones). BUT! for all other fields we do not do this.
        # This makes multiline fields inconsistent with the rest of the gang as
        # they have a trailing newline whereas others have not. To clean this
        # up we'll strip the fully assembled field value to drop the whitespaces
        # trailing the last line. As a result the string will no longer end
        # in a newline. This allows us to consinstently dump fields+\n when
        # generating output from this again. It also means fields are consistent
        # and one does not have to .strip everything for good measure.
        next unless multiline_fields.include?(field.downcase)

        data[field].rstrip!
      end

      mandatory_fields.each do |field|
        # TODO: this should really make a list and complain all at once or
        # something.
        raise "Missing mandatory field #{field}" unless data.include?(field)
      end

      data
    end
    # rubocop:enable

    def parse!
      raise 'Not implemented'
    end

    def dump_paragraph(data, fields = {})
      # mandatory_fields = fields[:mandatory] || []
      multiline_fields = fields[:multiline] || []
      foldable_fields = fields[:foldable] || []
      relationship_fields = fields[:relationship] || []

      output = ''
      data.each do |field, value|
        key = "#{field}: "
        output += key
        field = field.downcase # normalize for include check
        if multiline_fields.include?(field)
          output += output_multiline(value)
        elsif relationship_fields.include?(field)
          # relationships are always foldable but different than other
          # data as they are nested and have alternatives x|y
          output += output_relationship(value, key.length)
        elsif foldable_fields.include?(field)
          output += output_foldable(value, key.length)
        else
          # FIXME: rstrip because multiline do not get their trailing newline
          #   stripped in parsing
          output += (value || value.rstrip)
        end
        output += "\n"
      end
      output
    end

    private

    def output_multiline(data)
      data = data.join("\n") if data.respond_to?(:join)
      data = data.to_s unless data.is_a?(String)
      data.gsub("\n", "\n ").chomp(' ')
    end

    def output_relationship(data, indent)
      # This implements output as per wrap-and-sort. That is:
      #   - sort all
      #     - substvars at the end
      #   - output >80 => line break each entry
      joined_alternatives = data.collect do |entry|
        entry.join(' | ')
      end
      joined_alternatives = sort_relationships(joined_alternatives)
      output = joined_alternatives.join(', ')
      return output if output.size < (80 - indent)

      joined_alternatives.join(",\n#{Array.new(indent, ' ').join}")
    end

    def sort_relationships(array)
      array.sort do |x, y|
        x_var = x[0] == '$'
        y_var = y[0] == '$'
        # If x is a variable it loses to everything, if y is a var it loses
        # to everything. If both or none are vars regular alpha order applies.
        next 1 if x_var && !y_var
        next -1 if y_var && !x_var #

        x <=> y
      end
    end

    def output_foldable(data, indent)
      # This implements output as per wrap-and-sort. That is:
      #   - sort all
      #     - substvars at the end
      #   - output >80 => line break each entry
      data.sort
      output = data.collect(&:to_s).join(', ')
      return output if output.size < (80 - indent)

      data.collect(&:to_s).join(",\n#{Array.new(indent, ' ').join}")
    end
  end
end
