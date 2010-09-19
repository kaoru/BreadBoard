package Bread::Board;
use Moose;

use Bread::Board::Types;
use Bread::Board::ConstructorInjection;
use Bread::Board::SetterInjection;
use Bread::Board::BlockInjection;
use Bread::Board::Literal;
use Bread::Board::Container;
use Bread::Board::Container::Parameterized;
use Bread::Board::Dependency;
use Bread::Board::LifeCycle::Singleton;
use Bread::Board::Service::Inferred;

use Moose::Exporter;
Moose::Exporter->setup_import_methods(
    as_is => [qw[
        as
        container
        depends_on
        service
        wire_names
        include
        typemap
        infer
    ]],
);

our $AUTHORITY = 'cpan:STEVAN';
our $VERSION   = '0.15';

sub as (&) { $_[0] }

our $CC;

sub set_root_container {
    (defined $CC && confess "Cannot set the root container, CC is already defined $CC");
    $CC = shift;
}

sub container ($;$$) {
    my $name        = shift;
    my $name_is_obj = blessed $name && $name->isa('Bread::Board::Container') ? 1 : 0;

    my $c;
    if ( scalar @_ == 0 ) {
        return $name if $name_is_obj;
        return Bread::Board::Container->new(
            name => $name
        );
    }
    elsif ( scalar @_ == 1 ) {
        $c = $name_is_obj
            ? $name
            : Bread::Board::Container->new( name => $name );
    }
    else {
        confess 'container($object, ...) is not supported for parameterized containers'
            if $name_is_obj;
        my $param_names = shift;
        $c = Bread::Board::Container::Parameterized->new(
            name                    => $name,
            allowed_parameter_names => $param_names,
        )
    }
    my $body = shift;
    if (defined $CC) {
        $CC->add_sub_container($c);
    }
    if (defined $body) {
        local $_  = $c;
        local $CC = $c;
        $body->($c);
    }
    return $c;
}

sub include ($) {
    my $file = shift;
    if (my $ret = do $file) {
        return $ret;
    }
    else {
        confess "Couldn't compile $file: $@" if $@;
        confess "Couldn't open $file for reading: $!" if $!;
        confess "Unknown error when compiling $file";
    }
}

sub service ($@) {
    my $name = shift;
    my $s;
    if (scalar @_ == 1) {
        $s = Bread::Board::Literal->new(name => $name, value => $_[0]);
    }
    elsif (scalar(@_) % 2 == 0) {
        my %params = @_;
        my $type   = $params{service_type} || (exists $params{block} ? 'Block' : 'Constructor');
        $s = "Bread::Board::${type}Injection"->new(name => $name, %params);
    }
    else {
        confess "I don't understand @_";
    }
    $CC->add_service($s);
}

sub typemap ($@) {
    my $type = shift;

    (scalar @_ == 1)
        || confess "Too many (or too few) arguments to typemap";

    my $service;
    if (blessed $_[0]) {
        if ($_[0]->does('Bread::Board::Service')) {
            $service = $_[0];
        }
        elsif ($_[0]->isa('Bread::Board::Service::Inferred')) {
            $service = $_[0]->infer_service( $type );
        }
        else {
            confess "No idea what to do with a " . $_[0];
        }
    }
    else {
        $service = $CC->fetch( $_[0] );
    }

    $CC->add_type_mapping_for( $type, $service );
}

sub infer {
    my %params = @_;
    Bread::Board::Service::Inferred->new(
        current_container => $CC,
        service_args      => \%params,
        infer_params      => 1,
    );
}

sub wire_names { +{ map { $_ => depends_on($_) } @_ }; }

sub depends_on ($) {
    my $path = shift;
    Bread::Board::Dependency->new(service_path => $path);
}

__PACKAGE__->meta->make_immutable;

no Moose; 1;

__END__

=pod

=head1 NAME

Bread::Board - A solderless way to wire up your application components

=head1 SYNOPSIS

  use Bread::Board;

  my $c = container 'MyApp' => as {

      service 'log_file_name' => "logfile.log";

      service 'logger' => (
          class        => 'FileLogger',
          lifecycle    => 'Singleton',
          dependencies => [
              depends_on('log_file_name'),
          ]
      );

      container 'Database' => as {
          service 'dsn'      => "dbi:sqlite:dbname=my-app.db";
          service 'username' => "user234";
          service 'password' => "****";

          service 'dbh' => (
              block => sub {
                  my $s = shift;
                  DBI->connect(
                      $s->param('dsn'),
                      $s->param('username'),
                      $s->param('password'),
                  ) || die "Could not connect";
              },
              dependencies => wire_names(qw[dsn username password])
          );
      };

      service 'application' => (
          class        => 'MyApplication',
          dependencies => {
              logger => depends_on('logger'),
              dbh    => depends_on('Database/dbh'),
          }
      );

  };

  no Bread::Board; # removes keywords

  # get an instance of MyApplication
  # from the container
  my $app = $c->resolve( service => 'application' );

  # now user your MyApplication
  # as you normally would ...
  $app->run;

=head1 DESCRIPTION

Bread::Board is an inversion of control framework with a focus on
dependency injection and lifecycle management. It's goal is to
help you write more decoupled objects and components by removing
the need for you to manually wire those objects/components together.

Want to know more? See the L<Bread::Board::Manual>.

  +-----------------------------------------+
  |          A B C D E   F G H I J          |
  |-----------------------------------------|
  | o o |  1 o-o-o-o-o v o-o-o-o-o 1  | o o |
  | o o |  2 o-o-o-o-o   o-o-o-o-o 2  | o o |
  | o o |  3 o-o-o-o-o   o-o-o-o-o 3  | o o |
  | o o |  4 o-o-o-o-o   o-o-o-o-o 4  | o o |
  | o o |  5 o-o-o-o-o   o-o-o-o-o 5  | o o |
  |     |  6 o-o-o-o-o   o-o-o-o-o 6  |     |
  | o o |  7 o-o-o-o-o   o-o-o-o-o 7  | o o |
  | o o |  8 o-o-o-o-o   o-o-o-o-o 8  | o o |
  | o o |  9 o-o-o-o-o   o-o-o-o-o 9  | o o |
  | o o | 10 o-o-o-o-o   o-o-o-o-o 10 | o o |
  | o o | 11 o-o-o-o-o   o-o-o-o-o 11 | o o |
  |     | 12 o-o-o-o-o   o-o-o-o-o 12 |     |
  | o o | 13 o-o-o-o-o   o-o-o-o-o 13 | o o |
  | o o | 14 o-o-o-o-o   o-o-o-o-o 14 | o o |
  | o o | 15 o-o-o-o-o   o-o-o-o-o 15 | o o |
  | o o | 16 o-o-o-o-o   o-o-o-o-o 16 | o o |
  | o o | 17 o-o-o-o-o   o-o-o-o-o 17 | o o |
  |     | 18 o-o-o-o-o   o-o-o-o-o 18 |     |
  | o o | 19 o-o-o-o-o   o-o-o-o-o 19 | o o |
  | o o | 20 o-o-o-o-o   o-o-o-o-o 20 | o o |
  | o o | 21 o-o-o-o-o   o-o-o-o-o 21 | o o |
  | o o | 22 o-o-o-o-o   o-o-o-o-o 22 | o o |
  | o o | 22 o-o-o-o-o   o-o-o-o-o 22 | o o |
  |     | 23 o-o-o-o-o   o-o-o-o-o 23 |     |
  | o o | 24 o-o-o-o-o   o-o-o-o-o 24 | o o |
  | o o | 25 o-o-o-o-o   o-o-o-o-o 25 | o o |
  | o o | 26 o-o-o-o-o   o-o-o-o-o 26 | o o |
  | o o | 27 o-o-o-o-o   o-o-o-o-o 27 | o o |
  | o o | 28 o-o-o-o-o ^ o-o-o-o-o 28 | o o |
  +-----------------------------------------+

=head1 EXPORTED FUNCTIONS

=over 4

=item I<container ($name, &body)>

=item I<container ($container_instance, &body)>

=item I<container ($name, [ @parameters ], &body)>

=item I<as (&body)>

=item I<service ($name, $literal | %service_description)>

=item I<typemap ($type, $service | $service_path)>

=item I<infer (?%hints)>

=item I<depends_on ($service_path)>

=item I<wire_names (@service_names)>

=item I<include ($file)>

=back

=head1 EXAMPLE USING TYPEMAP

A new (read: experimental) feature of Bread::Board is typemapped services.
These are services which are mapped to a particular type rather then just
a name. This feature has the potential to make obsolete a large amount of the
Bread::Board configuration by simply asking Bread::Board to figure things
out on it's own. Here is a small example of how this works.

  # define the classes making sure
  # to specify required items and
  # their types

  {
      package Desk;
      use Moose;

      package Chair;
      use Moose;

      package Cubicle;
      use Moose;

      has 'desk'  => ( is => 'ro', isa => 'Desk',  required => 1 );
      has 'chair' => ( is => 'ro', isa => 'Chair', required => 1 );

      package Employee;
      use Moose;

      has [ 'first_name', 'last_name' ] => (
          is       => 'ro',
          isa      => 'Str',
          required => 1,
      );

      has 'work_area' => ( is => 'ro', isa => 'Cubicle', required => 1 );
  }

  # now create the container, and
  # map the Employee type and ask
  # Bread::Board to infer all the
  # other relationships

  my $c = container 'Initech' => as {
      typemap 'Employee' => infer;
  };

  # now you can create new Employee objects
  # by calling ->resolve with the type and
  # supplying the required parameters (see
  # below for details).

  my $micheal = $c->resolve(
      type       => 'Employee',
      parameters => {
          first_name => 'Micheal',
          last_name  => 'Bolton'
      }
  );

  my $cube = $micheal->work_area; # this will be a Cubicle object
  $cube->desk;  # this will be a Desk object
  $cube->chair; # this will be a Chair object

In the above example, we created a number of Moose classes that had
specific required relationships. When we called C<infer> for the
B<Employee> object, Bread::Board figured out those relationships
and set up dependencies and parameters accordingly.

For the C<work_area> object, we saw the B<Cubicle> type and then
basically called C<infer> on the B<Cubicle> object. We then saw
the B<Desk> and B<Chair> objects and called C<infer> on those as well.
The result of this recursive inferrence was that the B<Employee>,
B<Cubicle>, B<Desk> and B<Chair> relationships were modeled in
Bread::Board as dependent services.

Bread::Board also took it one step further.

We were able to resolve the B<Cubicle>, B<Desk> and B<Chair> types
automatically because they were already defined by Moose as subtypes
of the I<Object> type. We knew that it could introspect those classes
and get more information. However, this was not the case with the
I<first_name> and I<last_name> attributes of the B<Employee> object.
In that case, we determined that we couldn't resolve those objects and
(because it was a top-level inferrence) instead turned them into required
parameters for the inferred B<Employee> service.

And lastly, with a top-level inferrence (not one caused by recursion)
Bread::Board will also look at all the remaining non-required attributes
and turn them into optional parameters (see F<t/076_more_complex_typemap.t>
for an example of this).

This example should give a good basic overview of this feature and more
details can be found in the test suite. These show examples of how to
typemap roles to concrete classes and how to supply hints to C<infer>
to help Bread::Board figure out specific details.

As I mentioned above, this feature should be considered experimental
and we are still working out details and writing tests for it. Any
contributions are welcome.

=head1 ACKNOWLEDGEMENTS

Thanks to Daisuke Maki for his contributions and for really
pushing the development of this module along.

Chuck "sprongie" Adams, for testing/using early (pre-release)
versions of this module, and some good suggestions for naming
it.

Matt "mst" Trout, for finally coming up with the best name
for this module.

=head1 SEE ALSO

=over 4

=item L<IOC>

Bread::Board is basically my re-write of IOC.

=item L<http://en.wikipedia.org/wiki/Breadboard>

=back

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2007-2010 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
