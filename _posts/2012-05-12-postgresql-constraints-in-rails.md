---
layout: default
title: 'PostgreSQL Constraints in Rails'
category: articles
tags: [ruby rails postgresql databases]
---

### Motivation

The 'Rails way' is opinionated, and one of the those opinions is that model
validation is business logic and business logic belongs in application code.

However if

* there are other clients that don't use ActiveRecord to write to the
  database,
* your data is *very* important and you need to guarantee data
  integrity,
* you're a paranoid or disgruntled database admin and you don't trust any of
  these new fangled computating interweb machines or
* you're a careful responsible developer who wants to take advantage of all the
  tools available

then perhaps duplicating validation logic in ruby and in the database is a small
  price to pay.

It is also true that table wide validations like uniqueness enforced at the
application level can fail if two database connections write to the table at the
same time.

### Approach

My investigation is limited to PostgreSQL, my current favourite database, but I
am sure the MySQL equivalents are similar if not identical and are easy to look
up.

I first looked around the ruby community for gems or DSL's that can add column
and table constraints to my Rails migrations. I found a few, but in the end I
decided it would benefit me more to dig into PostgreSQL configuration instead of
adding more dependencies to my Gemfile.

### Gotchas

A few worries immediately spring to mind. Even assuming the constraints are
configured correctly and working they can make life difficult if you are not
careful.

The creation and deletion of data needs to be in order of dependency. This
includes the restoration of database backups, though this can be controlled by
temporarily disabling foreign key checking.

Another concern is how Rails and it's validations will cope with these
constraints. For example the Rails uniqueness validation actually queries the
database to establish the uniqueness of an attribute. If this validation is used
in conjunction with a unique constraint in the database this query is redundant.
Except that the error messages in the model would not be set by the database
constraint and there would be no form message to display.

Polymorphic associations also make things difficult because they cannot be
duplicated as simple foreign key constraints. (link)

One thing you definitely need to do is configure Rails to generate the schema in
sql format by adding

<pre>
<code class="ruby">
config.active_record.schema_format = :sql
</code>
</pre>

to your application's application.rb file. This actually replaces the Rails
migration DSL usually found in schema.rb with the database's own structure dump
utility.

### Models without validations or constraints

Starting with a simple example where we have users who can have many
projects.

<pre>
<code class="ruby">
class Project < ActiveRecord::Base
  belongs_to :user
end

class User < ActiveRecord::Base
  has_many :projects
end
</code>
</pre>

In this example the migration for the users table is not important. The
migration for the projects table will contain all of the constraints. We start
with the base unconstrained migration

<pre>
<code class="ruby">
class CreateProjects < ActiveRecord::Migration
  def change
    create_table :projects do |t|
      t.string :name
      t.string :state
      t.references :user
    end
  end
end
</code>
</pre>

But the resulting table is not entirely without constraints. This migration will
create a table with an additional integer column named id. This id column is the
primary key of this table (in PostgreSQL a table can only have one or zero
primary keys). Declaring a column as a primary key is the equivalent of adding a
unique index and a not null constraint to it.

The id column is also assigned a default value as the next value from a database
sequence. The sequence has a minimum value of 1 and a maximum value equal to the
maximum of a 64 bit signed integer.

The id column (at least in PostgreSQL) is a signed integer. PostgreSQL does not
support unsigned integers as a storage type, if it did it would amount to a not
negative constraint. In the case of the id which is assigned a sequence this
acts as a constraint, but this would not apply to the user_id integer field
which without any constraints can contain null, negative or zero values.

### Model validations

We can add our desired model constraints to our ActiveRecord models.

<pre>
<code class="ruby">
class Project < ActiveRecord::Base
  belongs_to :user
  validates :name, :uniqueness => { :case_sensitve => false },
    :presence => true
  validates :user, :presence => true
  validates :state, :inclusion => { :in => %w(active deleted) }
end

class User < ActiveRecord::Base
  has_many :projects, :dependent => :destroy
end
</code>
</pre>

We are specifying that a project must have a user_id, a case insensitve non null
unique name and state must be in either an be 'active' or 'deleted'.  On
Project.new.save! it will raise an ActiveRecord::RecordInvalid exception for
all the validations. We are also setting the dependent option to cascade
destruction of a user to the dependent projects.

### Migration constraints

Rails migrations do offer some basic cross database column constraints.

<pre>
<code class="ruby">
class CreateProjects < ActiveRecord::Migration
  def change
    create_table :projects do |t|
      t.string :name, :null => false,
      t.string :state, :limit => 16, :default => 'active', :null => false
      t.references :user, :null => false
    end
  end
end
</code>
</pre>

After this migration the database will prevent the user_id and the name column
in the projects table from containing null. Of course this is not a complete
implementation of the model validations. It does not mean user_id is a real user
id, in fact it will allow any integer

The database will also restrict the state string to 16 characters (an
arbitrarily chosen length) and requires that the state not be null. However we
do provide a default value for the state so we are able to create new projects
without specifying the state.

Instantly you see we have duplication, the state string 'active' is in the model
and the migration. Since the model classes are loaded in Rails migrations we
could use a class constant like Project::DEFAULT_STATE to remove this
duplication. But this still wouldn't be ideal since changing the default in the
model will not automatically change the database without a migration reset or
equivalent rebuild.

Assuming we have removed the model validations so they can't interfere, then we
will receive the exception

<pre>
<code class="ruby">
ActiveRecord::StatementInvalid:
PGError: ERROR:  null value in column "user_id" violates not-null constraint
</code>
</pre>

Note that the equivalent for the default for the state string in the migration
is a before_create callback. Just like the before_create the database default is
only applied during the initial insert and only when the state is not specified.
It may be that you want the default value to appear in the new form page, but
since the new form is constructed from an unpersisted model it won't have the
default state yet.

Alternatively, you could use the before_initialize which would apply every time
the object is initialized but then the state could never be nil even if it is
null in the database. Also, if you use before_create note that before_save is
run first so it would not have set the default yet for use in the before_save
callback.

### Adding indexes

Database indexes are not really constraints, their only purpose is to speed up
queries and joins. The ActiveRecord database drivers offer a database agnostic
way of added and removing indexes from tables.

<pre>
<code class="ruby">
class AddProjectConstraints < ActiveRecord::Migration
  def change
    add_index(:projects, :user_id)
  end
end
</code>
</pre>

The add_index method will also accept arrays of columns (for multi column
indexes), a unique switch (see later) and lengths for string indexes.

If any of the PostgreSQL index features are required it is possible to issue raw SQL
commands in the migration using the execute method. The equivalent to the
above migration is

<pre>
<code class="ruby">
class AddProjectConstraints < ActiveRecord::Migration
  def up
    execute 'create index user_id_idx on projects (user_id)'
  end

  def down
    execute 'drop index user_id_idx'
  end
end
</code>
</pre>

This will create a non-unique btree index on the user_id column. For more
information on the different kinds of index see the PostgreSQL
documentation.

Tip: If you want to add indexes to large production databases then it is worth
investigating concurrent index building.

### Foreign key

Arguably the most useful constraint that rails intentionally neglects are
foreign keys. These enforce the relations between the tables, the associations
between the models. The equivalent of the presence of user validation is

<pre>
<code class="ruby">
class AddProjectConstraints < ActiveRecord::Migration
  def up
    execute 'alter table projects add constraint fk_user '\
      'foreign key (user_id) references users(id)'
  end

  def down
    execute 'alter table projects drop constraint fk_user'
  end
end
</code>
</pre>

When trying to Project.new.save! a project with a non existent user id

<pre>
<code class="ruby">
ActiveRecord::InvalidForeignKey:
PGError: ERROR:  insert or update on table "projects"
violates foreign key constraint "fk_user"
DETAIL: Key (user_id)=(1) is not present in table "users".
</code>
</pre>

When trying to delete a user which is referred to by a project

<pre>
<code class="ruby">
ActiveRecord::InvalidForeignKey:
PGError: ERROR:  update or delete on table "users"
violates foreign key constraint "fk_user" on table "projects"
DETAIL: Key (id)=(1) is still referenced from table "projects".
</code>
</pre>

This is the default on delete behaviour, if we wanted to cascade deletes we
could change the constraint to

<pre>
<code class="sql">
alter table projects add constraint fk_league
foreign key (user_id) references users(id) on delete cascade
</code>
</pre>

then deleting the user deletes the projects. This is the equivalent of the
has_many dependent destroy configuration in the User model shown previously.
Obviously if we choose to let the database take care of the cascading deletes we
cannot expect the ActiveRecord destroy callbacks to trigger.

If we wanted user deletion to orphan the projects we would need to remove the
:null => false from the original project migration to allow the user_id to
be null and then with the migration

<pre>
<code class="sql">
alter table projects add constraint fk_league
  foreign key (user_id) references users(id) on delete set null
</code>
</pre>

As well as set null and the default no action there are other options
set default that sets the user_id to the default and restrict. The default
will wait till the end of the current transaction before complaining about the
key constraint whereas restrict will return an error straight away.

There is another option on update which determines what to do if the primary
key changes. For more information on foreign keys see the documentation.

Note that by declaring the foreign key constraint we are in effect replacing the
need for an unsigned integer constraint on the user_id column. This column is
constrained to a subset of the sequence assigned to the id column in the users
table.

### Uniqueness

Uniqueness can be added to a column with

<pre>
<code class="ruby">
class AddProjectConstraints < ActiveRecord::Migration
  def up
    execute 'alter table projects add constraint unique_name unique(name)'
  end

  def down
    execute 'alter table projects drop constraint unique_name'
  end
end
</code>
</pre>

This explicitly declares a column as unique and PostgreSQL will implement this
as it sees fit. This is implemented by automatically adding a unique index to
this table however this index was not visible for me in pgadmin in the same way
manually created indexes are. Despite this the PostgreSQL documentation
recommends if what you want is a uniqueness constraint then this is the
preferred way. When attempting to add duplicate named projects we get

<pre>
<code class="ruby">
ActiveRecord::RecordNotUnique: PGError: ERROR:  duplicate key value violates
unique constraint "unique_name"
DETAIL: Key (name)=(test) already exists.
</code>
</pre>

However, to reproduce the model validations exactly we want case insensitive
uniqueness. When I tried to add an expression to the add constraint command it
resulted in a syntax error, so I resorted to adding a unique index manually
with

<pre>
<code class="sql">
create unique index name_idx on projects (lower(name))
</code>
</pre>

This index is now visible in pgadmin alongside the foreign key index, and trying
to create a duplicate named record now results in the almost identical

<pre>
<code class="ruby">
ActiveRecord::RecordNotUnique: PGError: ERROR:  duplicate key value violates
unique constraint "name_idx"
DETAIL: Key (lower(name::text))=(test) already exists.
</code>
</pre>

Note: as an added bonus the unique index with the lower cased column value will
reduce the times of queries such as

<pre>
<code class="sql">
select * from projects where lower(name) = 'project 1'
</code>
</pre>

If adding the unique constraint is implemented by creating a unique index then I
would hope this index is also used for speeding up queries as well.

### Check

The equivalent of the state validation in the project model, and many other
simple single object validations, can be achieved by a check constraint.

<pre>
<code class="ruby">
class AddProjectConstraints < ActiveRecord::Migration
  def up
    execute "alter table projects add constraint check_state check (name in ('active', 'deleted'))"
  end

  def down
    execute 'alter table projects drop constraint check_state'
  end
end
</code>
</pre>

Trying to violate this constraint results in

<pre>
<code class="ruby">
ActiveRecord::StatementInvalid: PGError: ERROR:  new row for relation
"projects" violates check constraint "check_name"
</code>
</pre>

The check constraints simply take an SQL expression that evaluates to a boolean
and checks that it is true before allow an insert and update.

### References

* [Rails migrations](http://guides.rubyonrails.org/migrations.html)
* [Rails validations](http://guides.rubyonrails.org/active_record_validations_callbacks.html)
* [PostgreSQL constraints](http://www.postgresql.org/docs/9.1/static/ddl-constraints.html)
* [PostgreSQL indexes](http://www.postgresql.org/docs/9.1/static/indexes.html)

