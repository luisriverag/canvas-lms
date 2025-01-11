# frozen_string_literal: true

#
# Copyright (C) 2024 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

module Schemas
  class BaseSpecsTest < Base
    def self.schema
      {
        type: "object",
        properties: {
          some_str: { type: "string", enum: %w[foo bar] },
          some_num: { type: "number" },
          some_bool: { type: "boolean" },
          other_str: { type: "string" },
        },
        required: %w[some_str some_num],
      }
    end
  end

  class NestedValidationTest < Base
    def self.schema
      {
        type: "object",
        properties: {
          str1: { type: "string" },
          str2: { type: "string" },
          things: {
            type: "array",
            items: {
              type: "object",
              properties: {
                str3: { type: "string" },
                str4: { type: "string" },
                more_things: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      str5: { type: "string" },
                      str6: { type: "string" },
                    }
                  }
                }
              }
            }
          }
        }
      }
    end
  end

  describe Base do
    let(:bad_str_and_num) do
      { "some_str" => "waz", "some_num" => "not a number" }
    end

    describe ".simple_validation_errors" do
      describe "when values are of the wrong type/enum value" do
        subject { BaseSpecsTest.simple_validation_errors(bad_str_and_num) }

        it "returns one string for each error" do
          str_err = subject.grep(/some_str/).first
          num_err = subject.grep(/some_num/).first
          expect([str_err, num_err].sort).to eq(subject.sort)
        end

        it "includes the enum values and wrong value" do
          str_err = subject.grep(/some_str/).first
          %w[foo bar waz].each do |val|
            expect(str_err).to include(val)
          end
        end

        it "includes the required type" do
          num_err = subject.grep(/some_num/).first
          expect(num_err).to include("number")
        end
      end

      describe "when values are missing" do
        it "lists the missing keys" do
          res = BaseSpecsTest.simple_validation_errors({})
          expect(res.join).to include("some_str", "some_num")
        end
      end
    end

    describe "simple_validation_first_error" do
      it "returns nil if there are no errors" do
        good = { "some_str" => "foo", "some_num" => 42 }
        expect(BaseSpecsTest.simple_validation_first_error(good)).to be_nil
      end

      it "returns one error string" do
        res = BaseSpecsTest.simple_validation_first_error(bad_str_and_num)
        expect(res).to be_a(String)
      end

      describe "with error_format: :hash" do
        it "returns a hash with the error details" do
          res = BaseSpecsTest.simple_validation_first_error(bad_str_and_num, error_format: :hash)
          expect(res).to be_a(Hash)
          expect(res.keys).to contain_exactly(*%i[error field schema])
        end

        it "returns a hash with the error details if required fields are missing" do
          res = BaseSpecsTest.simple_validation_first_error({}, error_format: :hash)
          expect(res).to be_a(Hash)
          expect(res.keys).to contain_exactly(*%i[error schema details])
        end
      end
    end

    describe "validation_errors" do
      subject { BaseSpecsTest.validation_errors(hash) }

      let(:hash) { bad_str_and_num }

      it "returns an array of error strings" do
        res = subject
        expect(res).to be_a(Array)
        expect(res).to all(be_a(String))
      end

      context "with null values" do
        let(:hash) { { "other_str" => nil, "some_str" => "foo", "some_num" => 1234 } }

        it "errors" do
          expect(subject).to eq(["value at `/other_str` is not a string"])
        end

        context "when allow_nil: true" do
          subject { BaseSpecsTest.validation_errors(hash, allow_nil: true) }

          it "does not error" do
            expect(subject).to eq([])
          end
        end
      end

      context "with nested null values" do
        subject { NestedValidationTest.validation_errors(hash, allow_nil:) }

        let(:allow_nil) { false }
        let(:hash) do
          {
            "str1" => "foo",
            "str2" => nil,
            "things" => [
              {
                "str3" => "bar",
                "str4" => nil,
                "more_things" => [
                  "str5" => "baz",
                  "str6" => nil
                ]
              }
            ]
          }
        end

        it "errors" do
          expect(subject).to eq([
                                  "value at `/str2` is not a string",
                                  "value at `/things/0/str4` is not a string",
                                  "value at `/things/0/more_things/0/str6` is not a string"
                                ])
        end

        context "when allow_nil: true" do
          let(:allow_nil) { true }

          it "does not error" do
            expect(subject).to eq([])
          end
        end
      end
    end
  end
end
