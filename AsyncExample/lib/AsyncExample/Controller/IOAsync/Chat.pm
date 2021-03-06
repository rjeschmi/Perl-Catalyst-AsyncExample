package AsyncExample::Controller::IOAsync::Chat;

use Moose;
use MooseX::MethodAttributes;
use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;
use Protocol::WebSocket::URL;
use JSON;

extends 'Catalyst::Controller';

has 'history' => (
  is => 'bare',
  traits => ['Array'],
  isa  => 'ArrayRef[HashRef]',
  default => sub { +[] },
  handles => {
    history => 'elements',
    add_to_history => 'push'});

has 'clients' => (
  is => 'bare',
  traits => ['Array'],
  default => sub { +[] },
  handles => {
    clients => 'elements',
    add_client => 'push'});

sub start : ChainedParent
 PathPart('chat') CaptureArgs(0) { }

  sub index : Chained('start') PathPart('') GET Args(0)
  {
    my ($self, $ctx) = @_;
    my $uri = $ctx->req->uri;
    $ctx->stash(
      websocket_url => Protocol::WebSocket::URL->new(
        host=>$uri->host, port=>$uri->port,
          resource_name => '/ioasync/chat/ws'));

    $ctx->forward($ctx->view('HTML'));
  }

  sub ws : Chained('start') Args(0)
  {
    my ($self, $c) = @_;
    my $io = $c->req->io_fh;
    my $hs = Protocol::WebSocket::Handshake::Server
      ->new_from_psgi($c->req->env);

    $self->add_client($io);
    $io->configure(
      on_read => sub {
        my ($stream, $buff, $oef) = @_;
        if($hs->is_done) {
          (my $frame = $hs->build_frame)->append($$buff);
          while (my $message = $frame->next) {
            my $decoded = decode_json $message;
            if(my $user = $decoded->{new}) {
              $decoded = {username=>$user, message=>"Joined!"};
              foreach my $item ($self->history) {
                $stream->write(
                  $hs->build_frame(buffer=>encode_json($item))
                    ->to_bytes);
              }            
            }
            $self->add_to_history($decoded);
            foreach my $client($self->clients) {
              $client->write(
                $hs->build_frame(buffer=>encode_json($decoded))
                  ->to_bytes);
            }
          }
          return 0;
        } else {
          $hs->parse($$buff);
          $stream->write($hs->to_string);
          
        }
      }
    );
  }

__PACKAGE__->meta->make_immutable;

