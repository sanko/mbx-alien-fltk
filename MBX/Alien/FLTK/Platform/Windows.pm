package inc::MBX::Alien::FLTK::Platform::Windows;
{
    use strict;
    use warnings;
    use Carp qw[];
    use Config qw[%Config];
    use lib '../../../../../';
    use inc::MBX::Alien::FLTK::Utility qw[_o _a _rel _abs can_run];
    use inc::MBX::Alien::FLTK;
    use base 'inc::MBX::Alien::FLTK::Base';
    $|++;

    sub configure {
        my ($self) = @_;
        $self->quiet(1);
        $self->SUPER::configure();
        $self->notes(ldflags => $self->notes('ldflags')
                 . ' -mwindows -lmsimg32 -lole32 -luuid -lcomctl32 -lwsock32 '
        );
        $self->notes(
              'cxxflags' => ' -mwindows -DWIN32 ' . $self->notes('cxxflags'));
        $self->notes('define')->{'HAVE_STRCASECMP'}    = undef;
        $self->notes('define')->{'HAVE_STRNCASECMP'}   = undef;
        $self->notes('define')->{'HAVE_STRNCASECMP'}   = undef;
        $self->notes('define')->{'HAVE_DIRENT_H'}      = undef;
        $self->notes('define')->{'HAVE_SYS_NDIR_H'}    = undef;
        $self->notes('define')->{'HAVE_SYS_DIR_H'}     = undef;
        $self->notes('define')->{'HAVE_NDIR_H'}        = undef;
        $self->notes('define')->{'HAVE_SCANDIR'}       = undef;
        $self->notes('define')->{'HAVE_SCANDIR_POSIX'} = undef;
    GL: {
            last GL if !$self->find_h('GL/gl.h');
            print 'Testing GL Support... ';
            if (!$self->assert_lib({lib => 'opengl32', header => 'GL/gl.h'}))
            {   print "not okay\n";
                $self->_error({stage   => 'configure',
                               fatal   => 0,
                               message => 'OpenGL libs were not found'
                              }
                );
                last GL;
                for my $lib (keys %{$self->notes('libs_source')}) {
                    $self->notes('libs_source')->{$lib}{'disabled'}++
                        if $lib =~ m[gl$]i;
                }
            }
            print "okay\n";
            $self->notes('define')->{'HAVE_GL'} = 1;
            $self->notes(GL => '-lopengl32');
            last GL if !$self->find_h('GL/glu.h');
            print 'Testing GLU Support... ';
            if (!$self->assert_lib({lib => 'glu32', header => 'GL/glu.h'})) {
                print "not okay\n";
                $self->_error({stage   => 'configure',
                               fatal   => 0,
                               message => 'OpenGLU32 libs were not found'
                              }
                );
                last GL;
                for my $lib (keys %{$self->notes('libs_source')}) {
                    $self->notes('libs_source')->{$lib}{'disabled'}++
                        if $lib =~ m[gl$]i;
                }
            }
            else {
                $self->notes('define')->{'HAVE_GL_GLU_H'} = 1;
                print "okay\n";
                $self->notes(GL => ' -lglu32 ' . $self->notes('GL'));
            }
        }
        $self->quiet(0);
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
