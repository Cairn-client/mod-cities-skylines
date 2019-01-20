using CSM.Injections;

namespace CSM.Commands.Handler
{
    public class PropMoveHandler : CommandHandler<PropMoveCommand>
    {
        public override void Handle(PropMoveCommand command)
        {
            PropHandler.IgnoreProp.Add(command.PropID);
            PropManager.instance.MoveProp(command.PropID, command.Position);
            PropHandler.IgnoreProp.Remove(command.PropID);
        }
    }
}
