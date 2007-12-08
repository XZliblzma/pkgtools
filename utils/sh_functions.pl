#!/usr/bin/perl

# A script to list all the functions used in a shell script in a tree-like
# listing.

# (C) Ville Koskinen, 2005
# Released under the Artistic Licence.

use strict;
use warnings;

# Edit these.

# Separator to print between trees if handling multiple files.
my $separator = '-' x 5;

# What should the output of the node's children look like?
my $childstring = '|- '; 

# Print the functions in alphabetical order?
my $alphabetical = 0;

# Print number of uses in the file for each function? 
my $printusecount = 0;

# How deep should we go in the tree? Set this to 0 to print every subtree.
my $printlevel = 0;

# Print the functions used on the global level?
my $printglobal = 0;
# Set this to something unique, i.e. not a function in the file.
my $global = '__global__';

# If the function definition changes, change this variable accordingly.
# It's a Perl Regular Expression (perldoc perlre). Don't edit unless
# you know what you're doing.
my $functionre = '^\s*([a-z0-9_]+)(\s*)?\(\)';

# Do not edit below this.
####

sub print_help {
	print <<EOF
Usage: sh_functions.pl [file.sh] [...]

Print a tree-like structure of the functions defined and used in a
shell script file.sh. If given multiple files, print the trees 
separated with \'$separator\'.

EOF
;
}

# Create a tree of functions in the given file and return it.
sub create_tree {
	my ($file) = @_;

	unless (open (FILE, "< $file")) {
		warn "Can't open file $file";
		return undef;
	}

	my $tree = ();
	
	# See $functionre to know how functions are defined.
	# 
	# Since this is a shell script (sh, bash, etc.), every function
	# ends with a:
	# /^\s*\}/
	
	# This variable is set when we enter a function, and used when 
	# the information of which function uses which is stored in the
	# tree.
	my $in_function = $global;

	# Read the whole file and grep the function names. We need this
	# since it's not guaranteed that the functions are in order of
	# usage.
	while (my $line = <FILE>) {
		# Ignore comments.
		next if ($line =~ m/^#/);
		# Skip empty lines.
		next if ($line =~ m/^\s*$/);

		if ($line =~ m/$functionre/) {
			# Set the key value to something to let it known the function
			# exists.
			$tree->{$1}->{'count'} = 0;
			# This is preparing for the printing phase...
			$tree->{$1}->{'visited'} = 0;
		}
	}

	# Go to the beginning of the file.
	seek (FILE, 0, 0);

	# This time scan the functions used in each function.
	while (my $line = <FILE>) {
		# Ignore comments.
		next if ($line =~ m/^#/);
		# Skip empty lines.
		next if ($line =~ m/^\s*$/);

		# If we enter a function, set the name and continue to the next
		# line.
		if ($line =~ m/$functionre/) {
			$in_function = $1;
			
			next;
		}
		
		# Check if the line contains a known function. If it does,
		# make a note on it in the tree for the $in_function in question.
		if ($in_function) {
			foreach my $known_function (keys %$tree) {
				if ($line =~ m/\b$known_function\b/) {
					# Push it in the list
					$tree->{$in_function}->{'uses'}->{$known_function} = 1;
					
					# Increase its usage count.
					$tree->{$known_function}->{'count'}++;
				}
			}
		}

		# Here we leave a function.
		if ($line =~ m/^\s*}/) {
			$in_function = $global;

			next;
		}
	}

	close FILE;

	return $tree;
}

# Print the tree in a nice form. 
sub pretty_print {
	my ($tree, $level) = @_;

	return unless (defined $tree);
	
	my @keys;
	
	if ($alphabetical) {
		# Print the tree keys in alphabetical order.
		@keys = sort keys %$tree;
	}
	else {
		@keys = keys %$tree;
	}

	foreach my $key (@keys) {
		next if ($key eq $global and $printglobal eq 0);

		&print_key($tree, $key, 0);
		
		# If the function uses other functions, print them here.
		if (exists $tree->{$key}->{'uses'}) {
			my @children = undef;
			if ($alphabetical) {
				@children = sort keys %{ $tree->{$key}->{'uses'} };
			}
			else {
				@children = keys %{ $tree->{$key}->{'uses'} };
			}
			foreach my $use (@children) {
				&print_child($tree, $use, 0);
			}
		}
	}
}

# Print the child tree recursively.
sub print_child {
	my ($tree, $key, $level) = @_;

	return unless (defined $key);

	return if ($printlevel > 0 and $level >= $printlevel);

	my @keys = undef;
	if (exists $tree->{$key}->{'uses'}) {
		@keys = sort keys %{ $tree->{$key}->{'uses'} };
	}

	&print_key($tree, $key, $level + 1);

	foreach my $child (@keys) {
		&print_child($tree, $child, $level + 2);
	}
}

# Print the key.
sub print_key {
	my ($tree, $key, $level) = @_;

	if ($level > 0) {
		print '  ' x ($level - 1);
		print $childstring;
	}
	print $key;
	print " (", $tree->{$key}->{'count'}, ")" if (
		$printusecount and $key ne $global and $level eq 0);
	print "\n";
}
		

####

# If no arguments are given, print help and quit.
if (scalar(@ARGV) eq 0) {
	&print_help();
	exit 0;
}

my $count = scalar(@ARGV);

# Parse and print each file given on the command line.
foreach my $file (@ARGV) {
	&pretty_print( &create_tree($file) );

	print $separator, "\n" if (--$count);
}

