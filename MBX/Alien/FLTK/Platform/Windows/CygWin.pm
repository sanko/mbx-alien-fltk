package inc::MBX::Alien::FLTK::Platform::Windows::CygWin;
{
    use strict;
    use warnings;
    use Carp qw[];
    use Config qw[%Config];
    use lib '../../../../../../';
    use inc::MBX::Alien::FLTK::Utility qw[_o _a _rel _abs can_run];
    use inc::MBX::Alien::FLTK;
    use base 'inc::MBX::Alien::FLTK::Platform::Windows';
    use inc::MBX::Alien::FLTK::Platform::Unix;
    $|++;

    sub configure {
        my ($self) = @_;
        if (0 && 'enable_cygwin') {    # XXX - untested
            $self->inc::MBX::Alien::FLTK::Platform::Unix::configure(qw[no_gl])
                || last;
            $self->SUPER::configure(qw[no_base]);

            # XXX - Requires X11 support from Platform::Unix
            for my $type (qw[ldflags cxxflags cflags]) {
                $self->notes($type => $self->notes($type) . ' -D_WIN32 ');
            }
            return 1;
        }

        # Fallback which I hope works...
        $self->SUPER::configure();
        $self->inc::MBX::Alien::FLTK::Platform::Unix::configure(
                                                    qw[no_gl no_base no_x11]);
        $self->notes('define')->{'_WIN32'}       = 1;
        $self->notes('define')->{'USE_X11'}      = 0;
        $self->notes('define')->{'HAVE_SCANDIR'} = 1;
        for my $type (qw[ldflags cxxflags cflags]) {
            $self->notes($type => $self->notes($type) . ' -D_WIN32 ');
        }
        return 1;
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
