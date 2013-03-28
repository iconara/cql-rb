# encoding: utf-8

require 'spec_helper'

module Cql
  describe Sanitize do
    describe 'when there are no placeholders in the statement' do
      before do
        @statement = 'select * from table'
      end

      describe 'and no variables are given' do
        it 'returns the statement as-is' do
          subject.sanitize(@statement).should == @statement
        end
      end

      describe 'and one or more variables are given' do
        it 'throws InvalidBindVariableError' do
          expect {
            subject.sanitize(@statement, 1, 2)
          }.to raise_error(subject::InvalidBindVariableError)
        end
      end
    end

    describe 'when there are placeholders in the query' do
      describe 'and too few variables are given' do
        it 'throws InvalidBindVariableError' do
          expect {
            subject.sanitize('?')
          }.to raise_error(subject::InvalidBindVariableError)

          expect {
            subject.sanitize('? ?', 1)
          }.to raise_error(subject::InvalidBindVariableError)
        end
      end

      describe 'and too many variables are given' do
        it 'throws InvalidBindVariableError' do
          expect {
            subject.sanitize('? ?', 1, 2, 3)
          }.to raise_error(subject::InvalidBindVariableError)
        end
      end

      it 'replaces placeholders with the correct variable' do
        subject.sanitize('? ?', 1, 2.1).should == '1 2.1'
      end

      it 'quotes strings' do
        subject.sanitize('?', 'string').should == "'string'"
      end

      it 'escapes single quotes' do
        subject.sanitize('?', "a'b").should == "'a''b'"
      end

      it 'converts Dates' do
        subject.sanitize('?', Date.new(2013, 3, 26))
          .should == "'2013-03-26'"
      end

      it 'converts Times' do
        subject.sanitize('?', Time.new(2013, 3, 26, 23, 1, 2.544, 0))
          .should == 1364338862544.to_s
      end

      it 'converts Cql::Uuids to an bare string representation' do
        subject.sanitize('?', Cql::Uuid.new(2**127 - 1))
          .should == "7fffffff-ffff-ffff-ffff-ffffffffffff"
      end

      it 'converts binary strings into a hex blob' do
        subject.sanitize('?', [1,2,3,4].pack('C*'))
          .should == "0x01020304"
      end

      it 'joins elements of an array with a comma separator' do
        subject.sanitize('?', [1,2,3]).should == '1,2,3'
      end

      it 'joins key/value pairs of a hash with colon and comma separators' do
        subject.sanitize('?', {a: 1, b: 'z'}).should == "'a':1,'b':'z'"
      end
    end
  end
end