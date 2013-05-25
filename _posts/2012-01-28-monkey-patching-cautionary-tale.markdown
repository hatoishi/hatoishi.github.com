---
layout: default
title: 'Monkey Patching: Cautionary Tale'
category: ruby
tags : [ruby mongodb mongoid]
---

### The Gotcha #1

One of my current projects is a Ruby on Rails application that uses MongoDB for
persistence and Mongoid for the Object-Document-Mapper layer. One day I was
writing a test that froze time using the Timecop library and assigned a
Time.now.utc to a Mongoid field with the type Time. At a later point this time
was retrieved and compared to the original.

To my surprise asserting that these two times were equal failed despite the
formatted string versions of the times being identical. Inspecting the values
more closely I found that the system's Time.now.to_f provided 7 decimal places
(at least on my system) whereas the time retrieved from a Mongoid field had
none.  (This is true for un-persisted model fields not just fields reloaded from
the database).

### Investigating

According to the docs, MongoDB stores dates as the number of milliseconds since
the epoch in an integer. This millisecond limit is specified in the BSON
standard that MongoDB uses.

To confirm this I fired up a Rails console and issued the follow command several
times:

<pre>
<code class="ruby">
BSON.deserialize(
  BSON.serialize(id:Time.now.tap { |t| puts t.to_f })
).fetch('id').to_f
</code>
</pre>

The results confirmed that BSON was truncating to milliseconds. So even if
Mongoid wasn't truncating to the nearest second my tests would still have failed
because of BSON.

At this point I stopped investigating. I realised all databases would impose an
accuracy on their time values. It is probably good that Mongoid truncates values
automatically to the same accuracy as it knows the underlying database uses. The
only issue with Mongoid is that it appears to truncate more than MongoDB.

### Solution

In retrospect my first solution might have been a little bit heavy handed, but I
wanted to avoid this problem in the future. With this in mind I went about
monkey patching the Time.now method to truncate the times to the second. This
isn't such a stupid idea, the accuracy of this method is entirely arbitrary and
having it match the accuracy of the database makes sense. This monkey patching
was written in the spec_helper and so was only used in the test environment. I
really didn't anticipate any problem with this form of test wide 'accuracy
stubbing', certainly none of my code was dependant on timing fractions of
seconds.

### A Capybara Ate My Homework

Having successfully implemented the monkey patch and passed my unit tests I
moved on. I shouldn't have, I should have run all my tests. If I had I would
have made the connection between the monkey patch and the newly introduced error
in the acceptance tests.

The acceptance tests had started to complain that:

<pre>
time appears to be frozen, Capybara does not work with libraries which freeze
time, consider using time travelling instead
</pre>

Since I was using Timecop I started hunting through the test setup for unwanted
or un-returned time freezes. I couldn't find any, and I was actually able to
remove Timecop entirely from the test and it still reported time frozen.
Eventually I opened the Capybara gem and found that it detected frozen time with
something like:

<pre>
<code class="ruby">
start_time = Time.now
...
sleep(0.05)
raise Capybara::FrozenInTime,
  "time appears to be frozen..." if Time.now == start_time
</code>
</pre>

My newly monkey patched clock was ticking seconds now and had fooled Capybara
into thinking time had stopped.

### Final Solution

My final solution is to only freeze time at whole second times:

<pre>
<code class="ruby">
Timecop.freeze(Time.at(Time.now.to_i))
</code>
</pre>

After that all time increments with Timecop are whole seconds and the Rspec
equality matchers work with Time.now. An alternative would be to use the
be_close Rspec matcher.

### References

* [MongoDB docs](http://www.mongodb.org/display/DOCS/Dates)
* Look at strip_milliseconds method in
  [mongoid timekeeping.rb](https://github.com/mongoid/mongoid/blob/master/lib/mongoid/fields/internal/timekeeping.rb)
* Look at wait_until method in
  [capybara](https://github.com/jnicklas/capybara/blob/master/lib/capybara/node/base.rb)

