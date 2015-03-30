package Bread::Board::Traversable;
use Moose::Role;

with 'MooseX::Clone' => { -version => 0.05 };

has 'parent' => (
    is        => 'rw',
    isa       => 'Bread::Board::Traversable',
    weak_ref  => 1,
    clearer   => 'detach_from_parent',
    predicate => 'has_parent',
);

sub get_root_container {
    my $c = shift;
    while ($c->has_parent) {
        $c = $c->parent;
    }
    return $c;
}

sub fetch {
    my ($self, $path) = @_;

    my $root;
    if ($path =~ /^\//) {
        $root = $self->get_root_container;
    }
    else {
        $root = $self;
        while (!$root->isa('Bread::Board::Container')) {
            $root = $root->parent;
        }
    }

    my @path = grep { $_ } split /\// => $path;

    if ($path[0] eq '..') {
        my $c = $root;
        do {
            shift @path;
            $c = $c->parent
                 || confess "Expected parent for " . $c->name . " but found none";
        } while (defined $path[0] && $path[0] eq '..' && $c->has_parent);
        $root = $c;
    }

    return $root unless @path;

    my $c = $root;
    while (my $h = shift @path) {
        $c = _get_container_or_service($c, $h);
    }
    if (!$self->isa('Bread::Board::Service::Alias')) {
        my %seen;
        while ($c->isa('Bread::Board::Service::Alias')) {
            $c = $c->aliased_from;
            confess "Cycle detected in aliases" if exists $seen{$c};
            $seen{$c}++;
        }
    }
    return $c;
}

sub _get_container_or_service {
    my ($c, $name) = @_;

    (blessed $c)
        || confess "Expected object, got $c";

    if ($c->isa('Bread::Board::Dependency')) {
        # make sure to evaluate this from the parent
        return _get_container_or_service($c->parent->parent, $name);
    }

    if ($c->does('Bread::Board::Service::WithDependencies')) {
        return $c->get_dependency($name) if $c->has_dependency($name);
        confess "Could not find dependency ($name) from service " . $c->name;
    }

    # name() is implemented in Service and Container
    # get_sub_container and get_service is implemented in Container
    # there must be a better way to do this

    if ($c->does('Bread::Board::Service')) {
        if ($c->name eq $name) {
            warn "Traversing into the current service ($name) is deprecated."
               . " You should remove the $name component from the path.";
            return $c;
        }
    }
    elsif ($c->isa('Bread::Board::Container')) {
        if ($c->name eq $name) {
            warn "Traversing into the current container ($name) is deprecated;"
               . " you should remove the $name component from the path";
            return $c;
        }
        return $c->get_sub_container($name) if $c->has_sub_container($name);
        return $c->get_service($name)       if $c->has_service($name);
    }

    confess "Could not find container or service for $name in " . $c->name;
}

no Moose::Role; 1;

__END__

=pod

=head1 SYNOPSIS

  my $service = $container->fetch('/some/service/path');

  my $root = $service->get_root_container;

=head1 DESCRIPTION

This role provides the basic functionality to traverse a container /
service tree. Instances of classes consuming this role will get a
parent-child relationship between them.

=head1 METHODS

=over 4

=item B<parent>

Weak ref to another L<Bread::Board::Traversable> object, read/write
accessor (although you should probably not change this value directly
in normal code).

=item B<has_parent>

Predicate for the L</parent> attribute, true if a parent has been set.

=item B<detach_from_parent>

Clearer for the L</parent> attribute, you should probably not call
this method in normal code.

=item B<get_root_container>

Returns the farthest ancestor of the invocant, i.e. the top-most
container this object is a part of.

=item B<fetch>

  my $service = $this->fetch('/absolute/path');
  my $service = $this->fetch('relative/path');
  my $service = $this->fetch('../relative/path');

Given a (relative or absolute) path to a service or container, this
method walks the tree and returns the L<Bread::Board::Service> or
L<Bread::Board::Container> instance for that path. Dies if no object
can be found for the given path.

=back

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=cut
