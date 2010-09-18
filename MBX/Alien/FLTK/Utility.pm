package inc::MBX::Alien::FLTK::Utility;
{
    use strict;
    use warnings;
    use Config qw[%Config];
    use File::Spec::Functions qw[splitpath catpath catdir rel2abs];
    use File::Basename qw[];
    use Cwd qw[];
    use Exporter qw[import];
    our @EXPORT_OK
        = qw[can_run run _o _a _exe _dll _path _realpath _abs _rel _dir _file _split _cwd];

    sub can_run {    # Snagged from IPC::CMD and trimmed for my use
        my ($prog) = @_;

        # a lot of VMS executables have a symbol defined
        # check those first
        if ($^O eq 'VMS') {
            require VMS::DCLsym;
            my $syms = VMS::DCLsym->new;
            return $prog if scalar $syms->getsym(uc $prog);
        }
        require ExtUtils::MM;
        my @possible;
        for my $dir ((split /\Q$Config{path_sep}\E/, $ENV{PATH}),
                     File::Spec->curdir)
        {   my $abs = File::Spec->catfile($dir, $prog);
            push @possible, $abs if $abs = MM->maybe_command($abs);
        }
        return wantarray ? @possible : $possible[0];
    }
    sub run { return !system(join ' ', @_); }

    sub _o {
        my ($vol, $dir, $file) = splitpath(@_);
        $file =~ m[^(.*)(?:\..*)$] or return;
        return catpath($vol, $dir, ($1 ? $1 : $file) . $Config{'_o'});
    }

    sub _a {
        my ($vol, $dir, $file) = splitpath(@_);
        $file =~ m[^(.*)(?:\..*)$];
        return
            catpath($vol,
                    $dir,
                    ($1 && $1 =~ m[^lib] ? '' : 'lib')
                        . ($1 ? $1 : $file)
                        . $Config{'_a'}
            );
    }

    sub _exe {
        my ($vol, $dir, $file) = splitpath(@_);
        $file =~ m[^(.*)(?:\..*)$] or return @_;
        return catpath($vol, $dir, ($1 ? $1 : $file) . $Config{'_exe'});
    }

    sub _dll {
        my ($vol, $dir, $file) = splitpath(@_);
        $file =~ m[^(.*)(?:\..*)$] or return @_;
        return catpath($vol, $dir, ($1 ? $1 : $file) . '.' . $Config{'so'});
    }
    sub _path { File::Spec->catdir(@_) }

    sub _realpath {
        eval { Cwd::realpath(File::Spec->canonpath(shift)) };
    }
    sub _abs   { File::Spec->rel2abs(@_) }
    sub _rel   { File::Spec->abs2rel(@_) }
    sub _file  { File::Basename::basename(shift) }
    sub _dir   { File::Basename::dirname(shift || '') }
    sub _split { File::Spec->splitpath(@_) }
    sub _cwd   { Cwd::cwd(); }
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
