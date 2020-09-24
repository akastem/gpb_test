#!/usr/bin/perl

use 5.010;
use strict;
use warnings;

use Mojolicious::Lite;
use Config::Tiny;
use DBI;

use constant {
	CONFIG => Config::Tiny->read('config'),
	LIMIT  => 100,
};

my $dbh = DBI->connect(
	CONFIG->{mysql}->{dsn}, 
	CONFIG->{mysql}->{user},
	CONFIG->{mysql}->{password}
) or die 'Error connecting to database :(';

get '/' => sub {
	$_[0]->render(
		'template' => 'page',
		'notify'   => undef,
		'address'  => undef,
		'statuses' => undef,
		'messages' => undef
	)
};

post '/' => sub {
	my $self    = shift;
	my $address = $self->param('address');
	my $notify  = 'Неверно введён адрес!';

	if ($address =~ /^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$/) {
		my $notify = 'Записей, с данным получателем, не найдено!';

		my $statuses = $dbh->selectall_arrayref('
			SELECT SQL_CALC_FOUND_ROWS `created`, `str`, `int_id`
			FROM `log`
			WHERE `address` = ?
			ORDER BY `int_id`, `created`
			LIMIT ' . LIMIT,
			{'Slice' => {}}, $address
		);
		my $count = $dbh->selectrow_array('SELECT FOUND_ROWS()');

		if (@$statuses) {
			my %uniq;

			my $init_ids = join(',',
				map { $dbh->quote($_->{'int_id'}) }
				grep { !$uniq{$_->{'int_id'}}++ }
				@$statuses
			);

			my $messages = $init_ids ? $dbh->selectall_hashref('
				SELECT `created`, `str`, `int_id`
				FROM `message`
				WHERE `int_id` IN (' . $init_ids . ')',
				'int_id'
			) : {};

			$notify = $count > LIMIT ? sprintf('Записей, найденных с данным получателем, более %d!', LIMIT) : '';

			return $self->render(
				'template' => 'page',
				'notify'   => $notify,
				'address'  => $address,
				'statuses' => $statuses,
				'messages' => $messages
			);
		}
	}

	$self->render(
		'template' => 'page',
		'notify'   => $notify,
		'address'  => undef,
		'statuses' => undef,
		'messages' => undef
	);
};

app->start;

__DATA__
@@ page.html.ep
<!DOCTYPE html>
<html>
	<head>
		<meta http-equiv="Content-Type" content="text/html; charset=utf8">
		<title>Log Search</title>
	</head>
	<body>
		<style type="text/css">
			hr {
				border: none;
				color: #DDEFEF;
				background-color: #DDEFEF;
				height: 1px;
			}
			.search {
				text-align: center;
				margin-top: 20px;
			}
			.search div {
				font-size: 24px;
				margin-bottom: 5px;
			}
			.search form input[type="text"] {
				text-align: center;
				padding: 5px;
				width: 300px;
			}
			.search form input[type="submit"] {
				margin-top: 5px;
				border: none;
				padding: 5px 20px;
				cursor: pointer;
				background-color: #DDEFEF;
			}
			.result {
				margin: 20px 200px;
			}
			.result .notify {
				text-align: center;
				margin-bottom: 10px;
				background-color: #ffcccb;
				padding: 10px;
			}
			.result table {
				border: solid 1px #DDEEEE;
				border-collapse: collapse;
				border-spacing: 0;
				width: 100%;
			}
			.result table tr th {
				background-color: #DDEFEF;
				border: solid 1px #DDEEEE;
				color: #336B6B;
				padding: 10px;
				text-align: left;
				text-shadow: 1px 1px 1px #fff;
			}
			.result table tr td {
				border: solid 1px #DDEEEE;
				color: #333;
				padding: 10px;
				text-shadow: 1px 1px 1px #fff;
			}
		</style>

		<div class="search">
			<div>Log Search</div>
			<form method="post">
				<input type="text" value="<%= $address if defined $address %>" placeholder="address" name="address"><br/>
				<input type="submit" value="Поиск">
			</form>
		</div>
		<div class="result">
			<hr>
			% if (defined $notify) {
				<div class="notify"><%== $notify %></div>
			% }

			% if (defined $statuses && defined $messages) {
				<table>
					<tr>
						<th width="20%">Время создания записи</th>
						<th>Запись в лог</th>
					</tr>
					% my (%messages_show, $int_id);

					% for my $status (@$statuses) {
						% if ($int_id && $int_id ne $status->{'int_id'}) {
							<tr><td colspan="2">&nbsp;</td></tr>
						% }

						% $int_id = $status->{'int_id'};

						% unless ($messages_show{ $int_id }) {
							<tr>
								<td><%== $messages->{ $int_id }->{'created'} %></td>
								<td><%== $messages->{ $int_id }->{'str'} %></td>
							</tr>
							% $messages_show{ $int_id } = 1;
						% }
						<tr>
							<td><%== $status->{'created'} %></td>
							<td><%== $status->{'str'} %></td>
						</tr>
					% }
				</table>
			% }
		</div>
	</body>
</html>