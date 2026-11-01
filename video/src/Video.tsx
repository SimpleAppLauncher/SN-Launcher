import React from 'react';
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const INK = '#090c09';
const BONE = '#f6f1e7';
const MUTED = '#cfc9bb';
const SAGE = '#b8c8a8';
const WARM = '#d7a86b';

const FONT = '"Avenir Next", "Helvetica Neue", Helvetica, Arial, sans-serif';

const CLAMP = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

const fade = (frame: number, start: number, end: number, edge = 18) =>
  interpolate(frame, [start, start + edge, end - edge, end], [0, 1, 1, 0], CLAMP);

const rise = (frame: number, at: number, fps: number) => {
  const p = spring({
    frame: frame - at,
    fps,
    config: {damping: 200, stiffness: 110, mass: 0.9},
  });
  return {
    opacity: interpolate(p, [0, 1], [0, 1], CLAMP),
    transform: `translateY(${interpolate(p, [0, 1], [28, 0], CLAMP)}px)`,
  } as React.CSSProperties;
};

const Scene = ({
  start,
  end,
  children,
}: {
  start: number;
  end: number;
  children: React.ReactNode;
}) => {
  const frame = useCurrentFrame();
  if (frame < start - 1 || frame > end + 1) return null;
  return <AbsoluteFill style={{opacity: fade(frame, start, end)}}>{children}</AbsoluteFill>;
};

const Wordmark = ({small = false}: {small?: boolean}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: 13}}>
    <div
      style={{
        width: small ? 26 : 34,
        height: small ? 26 : 34,
        borderRadius: '50%',
        border: `1.5px solid ${SAGE}`,
        position: 'relative',
        boxSizing: 'border-box',
      }}
    >
      <div
        style={{
          position: 'absolute',
          left: 5,
          right: 5,
          top: '50%',
          height: 1,
          background: SAGE,
          opacity: 0.85,
        }}
      />
      <div
        style={{
          position: 'absolute',
          width: small ? 5 : 6,
          height: small ? 5 : 6,
          borderRadius: '50%',
          background: WARM,
          right: small ? 4 : 5,
          top: small ? 5 : 7,
        }}
      />
    </div>
    <span
      style={{
        color: BONE,
        fontFamily: FONT,
        fontWeight: 600,
        fontSize: small ? 19 : 25,
        letterSpacing: small ? 2.4 : 1.4,
      }}
    >
      SN-Launcher
    </span>
  </div>
);

const Label = ({children, style}: {children: React.ReactNode; style?: React.CSSProperties}) => (
  <div
    style={{
      color: SAGE,
      fontFamily: FONT,
      fontSize: 18,
      fontWeight: 600,
      letterSpacing: 4.2,
      textTransform: 'uppercase',
      ...style,
    }}
  >
    {children}
  </div>
);

const Headline = ({children, style}: {children: React.ReactNode; style?: React.CSSProperties}) => (
  <div
    style={{
      color: BONE,
      fontFamily: FONT,
      fontSize: 76,
      lineHeight: 1.02,
      fontWeight: 600,
      letterSpacing: -2.4,
      ...style,
    }}
  >
    {children}
  </div>
);

const Body = ({children, style}: {children: React.ReactNode; style?: React.CSSProperties}) => (
  <div
    style={{
      color: MUTED,
      fontFamily: FONT,
      fontSize: 28,
      lineHeight: 1.45,
      fontWeight: 400,
      ...style,
    }}
  >
    {children}
  </div>
);

const IntroScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  return (
    <Scene start={0} end={84}>
      <AbsoluteFill style={{backgroundColor: INK, overflow: 'hidden'}}>
        <div
          style={{
            position: 'absolute',
            width: 1150,
            height: 1150,
            right: -330,
            top: -340,
            borderRadius: '50%',
            background: `radial-gradient(circle, ${WARM}55 0%, ${WARM}18 38%, transparent 70%)`,
            filter: 'blur(12px)',
            transform: `scale(${interpolate(frame, [0, 84], [0.92, 1.08], CLAMP)})`,
          }}
        />
        <div
          style={{
            position: 'absolute',
            width: 900,
            height: 900,
            left: -360,
            bottom: -420,
            borderRadius: '50%',
            background: `radial-gradient(circle, ${SAGE}33 0%, transparent 68%)`,
            filter: 'blur(18px)',
          }}
        />
        <div
          style={{
            position: 'absolute',
            inset: 0,
            background:
              'linear-gradient(90deg, rgba(9,12,9,.92) 0%, rgba(9,12,9,.35) 58%, rgba(9,12,9,.72) 100%)',
          }}
        />

        <div
          style={{
            position: 'absolute',
            left: 132,
            top: 0,
            bottom: 0,
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'center',
          }}
        >
          <div style={rise(frame, 4, fps)}>
            <Wordmark />
          </div>
          <div
            style={{
              marginTop: 44,
              marginLeft: 2,
              width: 76,
              height: 2,
              background: WARM,
              transformOrigin: 'left',
              transform: `scaleX(${interpolate(frame, [8, 38], [0, 1], CLAMP)})`,
            }}
          />
          <div
            style={{
              ...rise(frame, 16, fps),
              marginTop: 38,
              maxWidth: 980,
            }}
          >
            <Headline style={{fontSize: 112, letterSpacing: -5.4, lineHeight: 0.98}}>
              A quieter
              <br />
              Android home.
            </Headline>
          </div>
          <div style={{...rise(frame, 30, fps), marginTop: 30}}>
            <Body style={{fontSize: 30}}>Your apps, your music, your photograph. Nothing shouting.</Body>
          </div>
        </div>

        <div
          style={{
            position: 'absolute',
            right: 128,
            bottom: 82,
            color: '#8f978b',
            fontFamily: FONT,
            fontSize: 15,
            letterSpacing: 3.4,
            opacity: interpolate(frame, [42, 62], [0, 1], CLAMP),
          }}
        >
          BUILT WITH FLUTTER
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

const HomeScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const zoom = interpolate(frame, [84, 240], [1.045, 1.135], CLAMP);
  const shift = interpolate(frame, [84, 240], [0, -18], CLAMP);

  return (
    <Scene start={84} end={240}>
      <AbsoluteFill style={{backgroundColor: INK, overflow: 'hidden'}}>
        <Img
          src={staticFile('home.jpg')}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            transform: `scale(${zoom}) translateY(${shift}px)`,
          }}
        />
        <AbsoluteFill
          style={{
            background:
              'linear-gradient(90deg, rgba(9,12,9,.72) 0%, rgba(9,12,9,.14) 52%, rgba(9,12,9,.12) 100%)',
          }}
        />
        <AbsoluteFill
          style={{
            background:
              'linear-gradient(to top, rgba(9,12,9,.88) 0%, rgba(9,12,9,.28) 43%, transparent 68%)',
          }}
        />

        <div
          style={{
            position: 'absolute',
            left: 104,
            right: 104,
            top: 70,
            bottom: 78,
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'flex-start',
          }}
        >
          <Wordmark small />
          <div style={{maxWidth: 840, marginTop: 286}}>
            <div style={rise(frame, 96, fps)}>
              <Label>01 / The home screen</Label>
            </div>
            <div style={{...rise(frame, 104, fps), marginTop: 22}}>
              <Headline>
                A home screen
                <br />
                that breathes.
              </Headline>
            </div>
            <div style={{...rise(frame, 120, fps), marginTop: 26, maxWidth: 720}}>
              <Body>
                A live photograph, rotated from Wikimedia Commons.
                <br />
                The rest waits until you ask for it.
              </Body>
            </div>
          </div>
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

const DockScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const zoom = interpolate(frame, [240, 366], [1.0, 1.035], CLAMP);
  const lift = 0;

  return (
    <Scene start={240} end={366}>
      <AbsoluteFill style={{backgroundColor: INK, overflow: 'hidden'}}>
        <Img
          src={staticFile('sheet.jpg')}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            objectPosition: 'center bottom',
            transform: `scale(${zoom}) translateY(${lift}px)`,
          }}
        />
        <AbsoluteFill
          style={{
            background:
              'linear-gradient(to bottom, rgba(9,12,9,.78) 0%, rgba(9,12,9,.12) 43%, transparent 65%)',
          }}
        />
        <AbsoluteFill
          style={{
            background:
              'linear-gradient(90deg, rgba(9,12,9,.62) 0%, rgba(9,12,9,.05) 55%, transparent 100%)',
          }}
        />

        <div
          style={{
            position: 'absolute',
            left: 104,
            right: 104,
            top: 66,
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'flex-start',
          }}
        >
          <div>
            <div style={rise(frame, 250, fps)}>
              <Wordmark small />
            </div>
            <div style={{...rise(frame, 260, fps), marginTop: 74}}>
              <Label>02 / One gesture</Label>
            </div>
            <div style={{...rise(frame, 268, fps), marginTop: 20, maxWidth: 760}}>
              <Headline>
                The essentials,
                <br />
                one gesture away.
              </Headline>
            </div>
            <div style={{...rise(frame, 284, fps), marginTop: 26, maxWidth: 640}}>
              <Body>The dock stays quiet until you reach for it.</Body>
            </div>
          </div>
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

const NowPlayingScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const cardLift = interpolate(frame, [371, 441], [34, 0], CLAMP);
  const cardScale = interpolate(frame, [371, 451], [0.965, 1], CLAMP);
  const glow = interpolate(frame, [345, 380, 465, 480], [0, 0.9, 0.9, 0], CLAMP);

  return (
    <Scene start={366} end={480}>
      <AbsoluteFill style={{backgroundColor: INK, overflow: 'hidden'}}>
        <Img
          src={staticFile('home.jpg')}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            filter: 'blur(24px) saturate(.72) brightness(.42)',
            transform: 'scale(1.16)',
          }}
        />
        <AbsoluteFill style={{backgroundColor: 'rgba(9,12,9,.38)'}} />
        <div
          style={{
            position: 'absolute',
            width: 1050,
            height: 620,
            right: -120,
            top: 230,
            borderRadius: '50%',
            background: `radial-gradient(circle, ${WARM}30 0%, transparent 68%)`,
            opacity: glow,
            filter: 'blur(20px)',
          }}
        />

        <div
          style={{
            position: 'absolute',
            left: 104,
            top: 70,
            bottom: 78,
            width: 720,
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'space-between',
          }}
        >
          <Wordmark small />
          <div>
            <div style={rise(frame, 377, fps)}>
              <Label>03 / Now playing</Label>
            </div>
            <div style={{...rise(frame, 385, fps), marginTop: 22}}>
              <Headline style={{fontSize: 68}}>
                Whatever is
                <br />
                playing, stays
                <br />
                in reach.
              </Headline>
            </div>
            <div style={{...rise(frame, 401, fps), marginTop: 28, maxWidth: 690}}>
              <Body style={{fontSize: 25}}>
                The card reads Android&apos;s media session.
                <br />
                Previous, play and next go to the app that owns the music.
              </Body>
            </div>
          </div>
        </div>

        <div
          style={{
            position: 'absolute',
            right: 96,
            top: 338,
            width: 930,
            transform: `translateY(${cardLift}px) scale(${cardScale}) rotate(-0.6deg)`,
            filter: 'drop-shadow(0 34px 80px rgba(0,0,0,.55))',
          }}
        >
          <div
            style={{
              borderRadius: 38,
              overflow: 'hidden',
              border: '1px solid rgba(255,255,255,.16)',
              background: '#f1f0eb',
            }}
          >
            <Img
              src={staticFile('now-playing.png')}
              style={{width: '100%', display: 'block', transform: 'scale(1.012)'}}
            />
          </div>
          <div
            style={{
              color: MUTED,
              fontFamily: FONT,
              fontSize: 15,
              letterSpacing: 2.8,
              marginTop: 22,
              textAlign: 'right',
              opacity: interpolate(frame, [401, 431], [0, 1], CLAMP),
            }}
          >
            ANDROID MEDIA SESSION
          </div>
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

const OutroScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  return (
    <Scene start={480} end={540}>
      <AbsoluteFill style={{backgroundColor: INK, overflow: 'hidden'}}>
        <Img
          src={staticFile('home.jpg')}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            filter: 'blur(34px) saturate(.6) brightness(.24)',
            transform: 'scale(1.18)',
          }}
        />
        <AbsoluteFill
          style={{
            background:
              'radial-gradient(circle at 50% 45%, rgba(9,12,9,.18) 0%, rgba(9,12,9,.9) 64%, #090c09 100%)',
          }}
        />
        <AbsoluteFill
          style={{
            alignItems: 'center',
            justifyContent: 'center',
            flexDirection: 'column',
            textAlign: 'center',
          }}
        >
          <div style={rise(frame, 489, fps)}>
            <Wordmark />
          </div>
          <div style={{...rise(frame, 497, fps), marginTop: 30}}>
            <Headline style={{fontSize: 86, letterSpacing: -3.6}}>A quieter Android home.</Headline>
          </div>
          <div
            style={{
              ...rise(frame, 509, fps),
              marginTop: 20,
              width: 86,
              height: 2,
              background: WARM,
              transformOrigin: 'center',
            }}
          />
          <div style={{...rise(frame, 519, fps), marginTop: 28}}>
            <Body style={{fontSize: 21, letterSpacing: 0.6}}>
              github.com/SimpleAppLauncher/SN-Launcher
            </Body>
          </div>
        </AbsoluteFill>
      </AbsoluteFill>
    </Scene>
  );
};

export const SnLauncherVideo = () => (
  <AbsoluteFill style={{backgroundColor: INK, fontFamily: FONT}}>
    <IntroScene />
    <HomeScene />
    <DockScene />
    <NowPlayingScene />
    <OutroScene />
  </AbsoluteFill>
);
