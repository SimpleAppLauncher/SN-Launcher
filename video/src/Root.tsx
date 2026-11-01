import {Composition} from 'remotion';
import {SnLauncherVideo} from './Video';

export const RemotionRoot = () => (
  <Composition
    id="SnLauncher"
    component={SnLauncherVideo}
    durationInFrames={1320}
    fps={30}
    width={1920}
    height={1080}
  />
);
