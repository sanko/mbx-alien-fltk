package inc::MBX::Alien::FLTK::Platform::Unix::Darwin;
{
    use strict;
    use warnings;
    use Carp qw[];
    use Config qw[%Config];
    use lib '../../../../../..';
    use inc::MBX::Alien::FLTK::Utility qw[_o _a _rel _abs can_run];
    use inc::MBX::Alien::FLTK;
    use base 'inc::MBX::Alien::FLTK::Platform::Unix';
    $|++;

    sub configure {
        my ($self) = @_;
        $self->SUPER::configure(qw[no_gl no_x11]) || return 0;
        $self->notes(    # MacOS X uses Carbon for graphics...
            ldflags =>
                ' -framework Carbon -framework Cocoa -framework ApplicationServices '
                . $self->notes('ldflags')
        );
        if ($self->notes('os_ver') >= 800) {

            # We know that Carbon is deprecated on OS X 10.4. To avoid
            # hundreds of warnings we will temporarily disable 'deprecated'
            # warnings on OS X.
            for my $type (qw[cxxflags cflags]) {
                $self->notes(  $type => ' -Wno-deprecated-declarations '
                             . $self->notes($type));
            }
        }

        # Starting with 10.6 (Snow Leopard), OS X does not support Carbon
        # calls anymore. We patch this until we are completely Cocoa compliant
        # by limiting ourselves to 32 bit Intel compiles
        my ($ver_rev) = (qx[sw_vers -productVersion] =~ m[([\.\d\d]+)]);
        my ($ver, $rev) = ($ver_rev =~ m[^(\d+)\.(\d+)$]);
        if (($ver > 10) || (($ver == 10) && $rev >= 5)) {
            $self->notes(ldflags => $self->notes('ldflags') . ' -arch i386 ');
            $self->notes(cflags  => $self->notes('cflags') . ' -arch i386 ');
            $self->notes(
                       cxxflags => $self->notes('cxxflags') . ' -arch i386 ');
        }
        $self->notes(GL => ' -framework AGL -framework OpenGL ');
        $self->notes('define')->{'USE_X11'}          = 0;
        $self->notes('define')->{'USE_QUARTZ'}       = 1;    # Alpha
        $self->notes('define')->{'__APPLE__'}        = 1;    # Alpha
        $self->notes('define')->{'__APPLE_QUARTZ__'} = 1;    # Alpha
        $self->notes('define')->{'__APPLE_COCOA__'}  = 1;    # Alpha
        return 1;
    }

    sub _configure_ar {
        my $s = shift;
        print 'Locating library archiver... ';
        open(my ($OLDOUT), ">&STDOUT");
        close *STDOUT;
        my ($ar) = grep { defined $_ } can_run($Config{'gar'}),
            can_run($Config{'ar'});
        open(*STDOUT, '>&', $OLDOUT)
            || exit !print "Couldn't restore STDOUT: $!\n";
        if (!$ar) {
            print "Could not find the library archiver, aborting.\n";
            exit 0;
        }
        $ar .= ' -r -c' . (can_run($Config{'ranlib'}) ? ' -s' : '');
        $s->notes(AR => $ar);
        print "$ar\n";
    }
    1;
}

=pod

=head1 Author

Sanko Robinson <sanko@cpan.org> - http://sankorobinson.com/

CPAN ID: SANKO

=head1 License and Legal

Copyright (C) 2009 by Sanko Robinson E<lt>sanko@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it under
the terms of The Artistic License 2.0. See the F<LICENSE> file included with
this distribution or http://www.perlfoundation.org/artistic_license_2_0.  For
clarification, see http://www.perlfoundation.org/artistic_2_0_notes.

When separated from the distribution, all POD documentation is covered by the
Creative Commons Attribution-Share Alike 3.0 License. See
http://creativecommons.org/licenses/by-sa/3.0/us/legalcode.  For
clarification, see http://creativecommons.org/licenses/by-sa/3.0/us/.

=for git $Id$

=cut
