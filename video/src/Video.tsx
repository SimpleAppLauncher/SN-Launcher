import React from 'react';
import {
  AbsoluteFill,
  Img,
  OffthreadVideo,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const BG = '#f7f4ec';
const PAPER = '#fffdf8';
const INK = '#141812';
const MUTED = '#62685f';
const LINE = '#ddd7c9';
const GREEN = '#4e6b52';
const SAGE = '#a9b8a0';
const WARM = '#d79a5b';
const SOFT = '#ece7da';

const FONT = '"Avenir Next", "Helvetica Neue", Helvetica, Arial, sans-serif';

const CLAMP = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

const rise = (frame: number, fps: number, delay = 0, dist = 26): React.CSSProperties => {
  const p = spring({
    frame: frame - delay,
    fps,
    config: {damping: 200, stiffness: 120, mass: 0.8},
  });
  return {
    opacity: interpolate(p, [0, 1], [0, 1], CLAMP),
    transform: `translateY(${interpolate(p, [0, 1], [dist, 0], CLAMP)}px)`,
  };
};

const reveal = (frame: number, start: number, end: number): React.CSSProperties => ({
  opacity: interpolate(frame, [start, end], [0, 1], CLAMP),
  transform: `translateY(${interpolate(frame, [start, end], [18, 0], CLAMP)}px)`,
});

const Wordmark = ({scale = 1}: {scale?: number}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: 12 * scale}}>
    <div
      style={{
        width: 34 * scale,
        height: 34 * scale,
        borderRadius: '50%',
        border: `1.6px solid ${GREEN}`,
        position: 'relative',
        boxSizing: 'border-box',
      }}
    >
      <div
        style={{
          position: 'absolute',
          left: 7 * scale,
          right: 7 * scale,
          top: '50%',
          height: 1.2,
          background: GREEN,
          opacity: 0.85,
        }}
      />
      <div
        style={{
          position: 'absolute',
          width: 6 * scale,
          height: 6 * scale,
          borderRadius: '50%',
          background: WARM,
          right: 5 * scale,
          top: 6 * scale,
        }}
      />
    </div>
    <span
      style={{
        color: INK,
        fontFamily: FONT,
        fontWeight: 650,
        fontSize: 22 * scale,
        letterSpacing: 0.1,
      }}
    >
      SN-Launcher
    </span>
  </div>
);

const Beta = () => (
  <div
    style={{
      padding: '7px 13px 6px',
      borderRadius: 999,
      border: `1px solid ${LINE}`,
      background: PAPER,
      color: GREEN,
      fontFamily: FONT,
      fontSize: 11,
      fontWeight: 700,
      letterSpacing: 2.6,
    }}
  >
    BETA
  </div>
);

const Header = ({section}: {section: string}) => (
  <div
    style={{
      position: 'absolute',
      left: 96,
      right: 96,
      top: 52,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      zIndex: 20,
    }}
  >
    <Wordmark />
    <div style={{display: 'flex', alignItems: 'center', gap: 20}}>
      <span
        style={{
          fontFamily: FONT,
          fontSize: 11,
          fontWeight: 700,
          letterSpacing: 3.4,
          color: MUTED,
        }}
      >
        {section}
      </span>
      <Beta />
    </div>
  </div>
);

const Label = ({children}: {children: React.ReactNode}) => (
  <div
    style={{
      fontFamily: FONT,
      fontSize: 12,
      fontWeight: 700,
      letterSpacing: 3.6,
      textTransform: 'uppercase',
      color: GREEN,
    }}
  >
    {children}
  </div>
);

const Headline = ({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: React.CSSProperties;
}) => (
  <div
    style={{
      fontFamily: FONT,
      color: INK,
      fontSize: 74,
      lineHeight: 1.02,
      fontWeight: 650,
      letterSpacing: -3.2,
      ...style,
    }}
  >
    {children}
  </div>
);

const Body = ({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: React.CSSProperties;
}) => (
  <div
    style={{
      fontFamily: FONT,
      color: MUTED,
      fontSize: 25,
      lineHeight: 1.5,
      fontWeight: 400,
      ...style,
    }}
  >
    {children}
  </div>
);

const Chip = ({children}: {children: React.ReactNode}) => (
  <div
    style={{
      display: 'inline-flex',
      alignItems: 'center',
      gap: 8,
      padding: '10px 15px 9px',
      borderRadius: 999,
      background: PAPER,
      border: `1px solid ${LINE}`,
      fontFamily: FONT,
      fontSize: 13,
      fontWeight: 600,
      letterSpacing: 0.2,
      color: MUTED,
    }}
  >
    <span style={{width: 6, height: 6, borderRadius: '50%', background: GREEN}} />
    {children}
  </div>
);

const Screen = ({
  src,
  width,
  video = false,
  startFrom = 0,
  endAt,
  playbackRate = 1,
  style,
  children,
  imgStyle,
}: {
  src: string;
  width: number;
  video?: boolean;
  startFrom?: number;
  endAt?: number;
  playbackRate?: number;
  style?: React.CSSProperties;
  children?: React.ReactNode;
  imgStyle?: React.CSSProperties;
}) => (
  <div
    style={{
      width,
      aspectRatio: '5 / 3',
      borderRadius: 26,
      background: '#ffffff',
      padding: 10,
      border: `1px solid ${LINE}`,
      boxSizing: 'border-box',
      boxShadow: '0 34px 80px rgba(20,24,18,.16), 0 1px 0 rgba(255,255,255,.9) inset',
      ...style,
    }}
  >
    <div
      style={{
        position: 'relative',
        width: '100%',
        height: '100%',
        borderRadius: 18,
        overflow: 'hidden',
        background: '#0b0d0b',
      }}
    >
      {video ? (
        <OffthreadVideo
          src={staticFile(src)}
          startFrom={startFrom}
          endAt={endAt}
          playbackRate={playbackRate}
          muted
          style={{width: '100%', height: '100%', objectFit: 'cover', ...imgStyle}}
        />
      ) : (
        <Img
          src={staticFile(src)}
          style={{width: '100%', height: '100%', objectFit: 'cover', ...imgStyle}}
        />
      )}
      {children}
    </div>
  </div>
);

const SceneFade = ({
  duration,
  children,
}: {
  duration: number;
  children: React.ReactNode;
}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 7, duration - 7, duration], [0, 1, 1, 0], CLAMP);
  return <AbsoluteFill style={{opacity}}>{children}</AbsoluteFill>;
};

const Backdrop = () => (
  <>
    <AbsoluteFill style={{backgroundColor: BG}} />
    <div
      style={{
        position: 'absolute',
        width: 1100,
        height: 1100,
        right: -360,
        top: -420,
        borderRadius: '50%',
        background: `radial-gradient(circle, ${SAGE}55 0%, ${SAGE}18 38%, transparent 70%)`,
      }}
    />
    <div
      style={{
        position: 'absolute',
        width: 760,
        height: 760,
        left: -320,
        bottom: -360,
        borderRadius: '50%',
        background: `radial-gradient(circle, ${WARM}24 0%, transparent 70%)`,
      }}
    />
    <div
      style={{
        position: 'absolute',
        inset: 0,
        backgroundImage: 'radial-gradient(rgba(20,24,18,.075) 1px, transparent 1px)',
        backgroundSize: '30px 30px',
        opacity: 0.55,
      }}
    />
    <div
      style={{
        position: 'absolute',
        left: 80,
        top: 0,
        bottom: 0,
        width: 1,
        background: 'linear-gradient(to bottom, transparent, rgba(20,24,18,.09), transparent)',
      }}
    />
    <div
      style={{
        position: 'absolute',
        right: 80,
        top: 0,
        bottom: 0,
        width: 1,
        background: 'linear-gradient(to bottom, transparent, rgba(20,24,18,.09), transparent)',
      }}
    />
  </>
);

const Intro = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  return (
    <AbsoluteFill>
      <Header section="00 / A CALMER HOME" />
      <div
        style={{
          position: 'absolute',
          left: 110,
          top: 196,
          width: 780,
        }}
      >
        <div style={rise(frame, fps, 2)}>
          <Label>SN-LAUNCHER · BETA</Label>
        </div>
        <div style={{...rise(frame, fps, 8), marginTop: 24}}>
          <Headline style={{fontSize: 94, letterSpacing: -5}}>
            A calmer
            <br />
            Android home.
          </Headline>
        </div>
        <div style={{...rise(frame, fps, 22), marginTop: 28, maxWidth: 700}}>
          <Body>
            Live photos, real app icons, and the music you are already playing.
            Nothing else asking for attention.
          </Body>
        </div>
        <div style={{...rise(frame, fps, 36), marginTop: 38, display: 'flex', gap: 10, flexWrap: 'wrap'}}>
          <Chip>Live photo frame</Chip>
          <Chip>Real app drawer</Chip>
          <Chip>Now-playing controls</Chip>
        </div>
      </div>

      <div
        style={{
          position: 'absolute',
          right: 90,
          top: 196,
          width: 820,
          opacity: interpolate(
            spring({frame: frame - 14, fps, config: {damping: 200, stiffness: 100, mass: 0.9}}),
            [0, 1],
            [0, 1],
            CLAMP,
          ),
          transform: `rotate(-2.5deg) translateY(${interpolate(
            spring({frame: frame - 14, fps, config: {damping: 200, stiffness: 100, mass: 0.9}}),
            [0, 1],
            [34, 0],
            CLAMP,
          )}px)`,
        }}
      >
        <Screen src="home-now-playing.jpg" width={820} />
        <div
          style={{
            marginTop: 18,
            display: 'flex',
            justifyContent: 'space-between',
            fontFamily: FONT,
            fontSize: 10,
            fontWeight: 700,
            letterSpacing: 2.6,
            color: MUTED,
          }}
        >
          <span>REAL HOME SCREEN</span>
          <span>NOKIA T20 · ANDROID 13</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const HomeScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const zoom = interpolate(frame, [0, 220], [1.015, 1.055], CLAMP);

  return (
    <AbsoluteFill>
      <Header section="01 / THE HOME SCREEN" />
      <div style={{position: 'absolute', left: 110, top: 220, width: 700}}>
        <div style={rise(frame, fps, 2)}>
          <Label>01 / THE HOME SCREEN</Label>
        </div>
        <div style={{...rise(frame, fps, 10), marginTop: 24}}>
          <Headline>
            A home
            <br />
            that breathes.
          </Headline>
        </div>
        <div style={{...rise(frame, fps, 24), marginTop: 28, maxWidth: 640}}>
          <Body>
            A live photograph from Wikimedia Commons, a real clock, and the
            weather. No feed, no folder clutter, no noise.
          </Body>
        </div>
        <div style={{...rise(frame, fps, 38), marginTop: 34, display: 'flex', gap: 10, flexWrap: 'wrap'}}>
          <Chip>Licence-checked photos</Chip>
          <Chip>Real time</Chip>
          <Chip>One quiet surface</Chip>
        </div>
        <div
          style={{
            ...reveal(frame, 74, 100),
            marginTop: 46,
            paddingTop: 20,
            borderTop: `1px solid ${LINE}`,
            maxWidth: 560,
            fontFamily: FONT,
            fontSize: 15,
            lineHeight: 1.5,
            color: MUTED,
          }}
        >
          Photo rotation is built in. It keeps six images ready, so the next
          one is already there when you ask for it.
        </div>
      </div>

      <div
        style={{
          position: 'absolute',
          right: 88,
          top: 174,
          width: 980,
          opacity: interpolate(
            spring({frame: frame - 8, fps, config: {damping: 200, stiffness: 100, mass: 0.9}}),
            [0, 1],
            [0, 1],
            CLAMP,
          ),
          transform: `translateY(${interpolate(
            spring({frame: frame - 8, fps, config: {damping: 200, stiffness: 100, mass: 0.9}}),
            [0, 1],
            [30, 0],
            CLAMP,
          )}px)`,
        }}
      >
        <Screen
          src="home.jpg"
          width={980}
          imgStyle={{transform: `scale(${zoom})`}}
          style={{transformOrigin: 'center'}}
        />
        <div
          style={{
            marginTop: 18,
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            fontFamily: FONT,
            fontSize: 10,
            fontWeight: 700,
            letterSpacing: 2.6,
            color: MUTED,
          }}
        >
          <span>LIVE PHOTO · WIKIMEDIA COMMONS</span>
          <span>REAL CLOCK · REAL WEATHER</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const DockScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  return (
    <AbsoluteFill>
      <Header section="02 / ONE GESTURE" />
      <div style={{position: 'absolute', left: 110, top: 220, width: 660}}>
        <div style={rise(frame, fps, 2)}>
          <Label>02 / ONE GESTURE</Label>
        </div>
        <div style={{...rise(frame, fps, 10), marginTop: 24}}>
          <Headline>
            Every app.
            <br />
            One gesture.
          </Headline>
        </div>
        <div style={{...rise(frame, fps, 24), marginTop: 28, maxWidth: 610}}>
          <Body>
            Pull up for the apps you actually use. Keep pulling for a searchable
            drawer with real installed-app icons — no folders to curate.
          </Body>
        </div>
        <div style={{...rise(frame, fps, 38), marginTop: 34, display: 'flex', gap: 10, flexWrap: 'wrap'}}>
          <Chip>Real icons</Chip>
          <Chip>Search</Chip>
          <Chip>No folders</Chip>
        </div>
      </div>

      <div
        style={{
          position: 'absolute',
          right: 88,
          top: 158,
          width: 1010,
          opacity: interpolate(
            spring({frame: frame - 10, fps, config: {damping: 200, stiffness: 100, mass: 0.9}}),
            [0, 1],
            [0, 1],
            CLAMP,
          ),
          transform: `translateY(${interpolate(
            spring({frame: frame - 10, fps, config: {damping: 200, stiffness: 100, mass: 0.9}}),
            [0, 1],
            [28, 0],
            CLAMP,
          )}px)`,
        }}
      >
        <Screen
          src="demo.mp4"
          video
          startFrom={90}
          endAt={300}
          playbackRate={0.7}
          width={1010}
        />
        <div
          style={{
            marginTop: 18,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
          }}
        >
          <div style={{display: 'flex', alignItems: 'center', gap: 9}}>
            <span
              style={{
                width: 7,
                height: 7,
                borderRadius: '50%',
                background: GREEN,
                boxShadow: `0 0 0 4px ${GREEN}18`,
              }}
            />
            <span
              style={{
                fontFamily: FONT,
                fontSize: 10,
                fontWeight: 700,
                letterSpacing: 2.6,
                color: MUTED,
              }}
            >
              REAL CAPTURE · NOKIA T20
            </span>
          </div>
          <span
            style={{
              fontFamily: FONT,
              fontSize: 10,
              fontWeight: 700,
              letterSpacing: 2.6,
              color: MUTED,
            }}
          >
            2000 × 1200 · LANDSCAPE
          </span>
        </div>
        <div
          style={{
            marginTop: 24,
            display: 'flex',
            alignItems: 'center',
            gap: 18,
            fontFamily: FONT,
            fontSize: 12,
            fontWeight: 700,
            letterSpacing: 1.8,
            color: MUTED,
          }}
        >
          <span>PULL UP</span>
          <span style={{width: 28, height: 1, background: LINE}} />
          <span>SEE ALL</span>
          <span style={{width: 28, height: 1, background: LINE}} />
          <span>SEARCH</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const NowPlayingScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pulse = interpolate(frame, [40, 62, 84, 106], [0.35, 1, 1, 0.35], CLAMP);

  return (
    <AbsoluteFill>
      <Header section="03 / NOW PLAYING" />
      <div style={{position: 'absolute', left: 110, top: 210, width: 660}}>
        <div style={rise(frame, fps, 2)}>
          <Label>03 / NOW PLAYING</Label>
        </div>
        <div style={{...rise(frame, fps, 10), marginTop: 24}}>
          <Headline>
            Music,
            <br />
            in reach.
          </Headline>
        </div>
        <div style={{...rise(frame, fps, 24), marginTop: 28, maxWidth: 610}}>
          <Body>
            See what is playing in any app — Spotify, YouTube, a podcast, even
            picture-in-picture. Play, pause and skip without leaving home.
          </Body>
        </div>
        <div style={{...rise(frame, fps, 38), marginTop: 34, display: 'flex', gap: 10, flexWrap: 'wrap'}}>
          <Chip>Spotify</Chip>
          <Chip>YouTube</Chip>
          <Chip>Podcasts</Chip>
        </div>
      </div>

      <div
        style={{
          position: 'absolute',
          right: 92,
          top: 152,
          width: 930,
          opacity: interpolate(
            spring({frame: frame - 12, fps, config: {damping: 200, stiffness: 100, mass: 0.9}}),
            [0, 1],
            [0, 1],
            CLAMP,
          ),
          transform: `translateY(${interpolate(
            spring({frame: frame - 12, fps, config: {damping: 200, stiffness: 100, mass: 0.9}}),
            [0, 1],
            [28, 0],
            CLAMP,
          )}px)`,
        }}
      >
        <Screen src="home-now-playing.jpg" width={930}>
          <div
            style={{
              position: 'absolute',
              left: '62.0%',
              top: '2.25%',
              width: '35.2%',
              height: '11.9%',
              border: `2px solid rgba(169, 207, 154, ${0.45 + pulse * 0.55})`,
              borderRadius: 22,
              boxShadow: `0 0 0 7px rgba(169, 207, 154, ${0.12 * pulse})`,
            }}
          />
        </Screen>
        <div
          style={{
            marginTop: 18,
            display: 'flex',
            justifyContent: 'space-between',
            fontFamily: FONT,
            fontSize: 10,
            fontWeight: 700,
            letterSpacing: 2.6,
            color: MUTED,
          }}
        >
          <span>REAL HOME SCREEN · TOP-RIGHT STRIP</span>
          <span>CONTROLS GO TO THE OWNING APP</span>
        </div>
      </div>

      <div
        style={{
          position: 'absolute',
          left: 110,
          bottom: 82,
          width: 600,
          opacity: interpolate(frame, [62, 86], [0, 1], CLAMP),
          transform: `translateY(${interpolate(frame, [62, 86], [18, 0], CLAMP)}px)`,
        }}
      >
        <div
          style={{
            background: PAPER,
            border: `1px solid ${LINE}`,
            borderRadius: 18,
            padding: 14,
            boxShadow: '0 18px 44px rgba(20,24,18,.10)',
          }}
        >
          <Img
            src={staticFile('now-playing-strip.jpg')}
            style={{width: '100%', borderRadius: 12, display: 'block'}}
          />
          <div
            style={{
              marginTop: 12,
              display: 'flex',
              justifyContent: 'space-between',
              fontFamily: FONT,
              fontSize: 9,
              fontWeight: 700,
              letterSpacing: 2.2,
              color: MUTED,
            }}
          >
            <span>READ FROM ANDROID&apos;S MEDIA SESSION</span>
            <span>PREV · PLAY · NEXT</span>
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const Bar = ({
  label,
  value,
  max,
  color,
  delay,
  suffix = 'ms',
}: {
  label: string;
  value: number;
  max: number;
  color: string;
  delay: number;
  suffix?: string;
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const p = spring({frame: frame - delay, fps, config: {damping: 200, stiffness: 90, mass: 0.8}});
  const width = interpolate(p, [0, 1], [0, (value / max) * 100], CLAMP);

  return (
    <div style={{marginTop: 22}}>
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'baseline',
          fontFamily: FONT,
          fontSize: 14,
          color: MUTED,
          fontWeight: 600,
        }}
      >
        <span>{label}</span>
        <span style={{color: INK, fontWeight: 700}}>
          {Math.round(value)}
          {suffix}
        </span>
      </div>
      <div
        style={{
          marginTop: 9,
          height: 12,
          borderRadius: 999,
          background: SOFT,
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            width: `${width}%`,
            height: '100%',
            borderRadius: 999,
            background: color,
          }}
        />
      </div>
    </div>
  );
};

const Stat = ({
  value,
  label,
  sub,
  delay,
}: {
  value: string;
  label: string;
  sub: string;
  delay: number;
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <div
      style={{
        ...rise(frame, fps, delay, 18),
        background: PAPER,
        border: `1px solid ${LINE}`,
        borderRadius: 18,
        padding: '22px 22px 20px',
        minHeight: 132,
      }}
    >
      <div
        style={{
          fontFamily: FONT,
          fontSize: 38,
          lineHeight: 1,
          fontWeight: 650,
          letterSpacing: -1.4,
          color: INK,
        }}
      >
        {value}
      </div>
      <div
        style={{
          marginTop: 12,
          fontFamily: FONT,
          fontSize: 12,
          fontWeight: 700,
          letterSpacing: 1.6,
          textTransform: 'uppercase',
          color: GREEN,
        }}
      >
        {label}
      </div>
      <div style={{marginTop: 5, fontFamily: FONT, fontSize: 13, color: MUTED}}>{sub}</div>
    </div>
  );
};

const PerformanceScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  return (
    <AbsoluteFill>
      <Header section="04 / PERFORMANCE" />
      <div style={{position: 'absolute', left: 110, top: 196, width: 700}}>
        <div style={rise(frame, fps, 2)}>
          <Label>04 / PERFORMANCE</Label>
        </div>
        <div style={{...rise(frame, fps, 10), marginTop: 24}}>
          <Headline>
            Measured,
            <br />
            not promised.
          </Headline>
        </div>
        <div style={{...rise(frame, fps, 24), marginTop: 28, maxWidth: 640}}>
          <Body>
            Five warm launches on the Nokia T20, Android 13. The point is not a
            faster number. It is everything you get without giving up speed.
          </Body>
        </div>
        <div
          style={{
            ...rise(frame, fps, 38),
            marginTop: 34,
            display: 'inline-flex',
            alignItems: 'center',
            gap: 9,
            fontFamily: FONT,
            fontSize: 11,
            fontWeight: 700,
            letterSpacing: 2.2,
            color: MUTED,
          }}
        >
          <span style={{width: 7, height: 7, borderRadius: '50%', background: GREEN}} />
          TEST DEVICE · NOKIA T20 · 1200 × 2000
        </div>
      </div>

      <div style={{position: 'absolute', right: 90, top: 174, width: 900}}>
        <div
          style={{
            ...rise(frame, fps, 10, 22),
            background: PAPER,
            border: `1px solid ${LINE}`,
            borderRadius: 22,
            padding: '26px 28px 24px',
            boxShadow: '0 24px 60px rgba(20,24,18,.09)',
          }}
        >
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'baseline',
              fontFamily: FONT,
            }}
          >
            <div style={{fontSize: 11, fontWeight: 700, letterSpacing: 2.6, color: MUTED}}>
              WARM OPEN · MEDIAN OF 5
            </div>
            <div style={{fontSize: 11, fontWeight: 700, letterSpacing: 2.2, color: GREEN}}>
              ON PAR WITH STOCK
            </div>
          </div>
          <Bar label="SN-Launcher" value={144} max={160} color={GREEN} delay={26} />
          <Bar label="Stock launcher" value={140} max={160} color="#b9b4a6" delay={34} />
          <div
            style={{
              marginTop: 20,
              paddingTop: 16,
              borderTop: `1px solid ${LINE}`,
              fontFamily: FONT,
              fontSize: 15,
              lineHeight: 1.45,
              color: MUTED,
            }}
          >
            <span style={{color: INK, fontWeight: 700}}>0.14 s both.</span>{' '}
            A home screen is always resident, so warm open is the honest number.
          </div>
        </div>

        <div
          style={{
            ...rise(frame, fps, 40, 18),
            marginTop: 14,
            padding: '16px 20px',
            background: PAPER,
            border: `1px solid ${LINE}`,
            borderRadius: 18,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 20,
          }}
        >
          <div>
            <div
              style={{
                fontFamily: FONT,
                fontSize: 12,
                fontWeight: 700,
                letterSpacing: 2.2,
                color: GREEN,
              }}
            >
              IDLE CPU · 60 S SAMPLE
            </div>
            <div
              style={{
                marginTop: 6,
                fontFamily: FONT,
                fontSize: 14,
                lineHeight: 1.4,
                color: MUTED,
              }}
            >
              Screen on, default home, other launcher disabled.
              {' '}Stock measured 0.15% of one core.
            </div>
          </div>
          <div
            style={{
              fontFamily: FONT,
              fontSize: 38,
              fontWeight: 650,
              letterSpacing: -1.4,
              color: INK,
              whiteSpace: 'nowrap',
            }}
          >
            3.3%
          </div>
        </div>

        <div
          style={{
            marginTop: 18,
            display: 'grid',
            gridTemplateColumns: '1fr 1fr',
            gap: 14,
          }}
        >
          <Stat value="10 MB" label="APK size" sub="Flutter + native bridge" delay={46} />
          <Stat value="Android 7+" label="min SDK 24" sub="Wide device support" delay={52} />
          <Stat value="2000 × 1200" label="tablet-native" sub="Landscape layout" delay={58} />
          <Stat value="Live" label="media updates" sub="No relaunch needed" delay={64} />
        </div>
      </div>
    </AbsoluteFill>
  );
};

const CompareRow = ({
  label,
  stock,
  sn,
  delay,
}: {
  label: string;
  stock: string;
  sn: string;
  delay: number;
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <div
      style={{
        ...rise(frame, fps, delay, 12),
        display: 'grid',
        gridTemplateColumns: '170px 1fr 1fr',
        alignItems: 'center',
        gap: 24,
        padding: '13px 0',
        borderTop: `1px solid ${LINE}`,
        fontFamily: FONT,
        fontSize: 19,
      }}
    >
      <div style={{fontSize: 11, fontWeight: 700, letterSpacing: 2.2, color: MUTED}}>{label}</div>
      <div style={{color: MUTED}}>{stock}</div>
      <div style={{display: 'flex', alignItems: 'center', gap: 9, color: INK, fontWeight: 600}}>
        <span style={{width: 6, height: 6, borderRadius: '50%', background: GREEN}} />
        {sn}
      </div>
    </div>
  );
};

const CompareScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  return (
    <AbsoluteFill>
      <Header section="05 / THE DIFFERENCE" />
      <div style={{position: 'absolute', left: 110, top: 130, width: 820}}>
        <div style={rise(frame, fps, 2)}>
          <Label>05 / THE DIFFERENCE</Label>
        </div>
        <div style={{...rise(frame, fps, 10), marginTop: 18}}>
          <Headline style={{fontSize: 58, letterSpacing: -2.4}}>
            Same tablet. A calmer default.
          </Headline>
        </div>
      </div>
      <div
        style={{
          position: 'absolute',
          right: 96,
          top: 152,
          fontFamily: FONT,
          fontSize: 11,
          fontWeight: 700,
          letterSpacing: 2.2,
          color: MUTED,
        }}
      >
        STOCK ANDROID 13 · SIDE BY SIDE
      </div>

      <div style={{position: 'absolute', left: 180, top: 274, width: 700}}>
        <div
          style={{
            marginBottom: 12,
            fontFamily: FONT,
            fontSize: 10,
            fontWeight: 700,
            letterSpacing: 2.4,
            color: MUTED,
          }}
        >
          STOCK LAUNCHER
        </div>
        <Screen
          src="stock.jpg"
          width={700}
          style={{
            opacity: interpolate(frame, [8, 26], [0, 1], CLAMP),
            transform: `translateY(${interpolate(frame, [8, 26], [18, 0], CLAMP)}px)`,
          }}
        />
      </div>

      <div style={{position: 'absolute', right: 180, top: 274, width: 700}}>
        <div
          style={{
            marginBottom: 12,
            fontFamily: FONT,
            fontSize: 10,
            fontWeight: 700,
            letterSpacing: 2.4,
            color: GREEN,
          }}
        >
          SN-LAUNCHER · BETA
        </div>
        <Screen
          src="home.jpg"
          width={700}
          style={{
            opacity: interpolate(frame, [14, 32], [0, 1], CLAMP),
            transform: `translateY(${interpolate(frame, [14, 32], [18, 0], CLAMP)}px)`,
          }}
        />
      </div>

      <div style={{position: 'absolute', left: 180, right: 180, top: 760}}>
        <CompareRow label="HOME" stock="Static wallpaper" sn="Live photo frame" delay={34} />
        <CompareRow label="APPS" stock="Grid + folders" sn="Searchable real-icon drawer" delay={40} />
        <CompareRow label="MUSIC" stock="No home controls" sn="Now-playing + transport" delay={46} />
        <CompareRow label="DEFAULT" stock="Widgets & feed" sn="One quiet digest" delay={52} />
      </div>

      <div
        style={{
          position: 'absolute',
          left: 180,
          right: 180,
          bottom: 54,
          display: 'flex',
          justifyContent: 'space-between',
          fontFamily: FONT,
          fontSize: 11,
          fontWeight: 700,
          letterSpacing: 2.2,
          color: MUTED,
        }}
      >
        <span>BOTH CAPTURED ON THE SAME NOKIA T20</span>
        <span>NO MOCKUPS</span>
      </div>
    </AbsoluteFill>
  );
};

const Outro = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          textAlign: 'center',
          ...rise(frame, fps, 2),
        }}
      >
        <Wordmark scale={1.35} />
        <div style={{...rise(frame, fps, 10), marginTop: 30}}>
          <Headline style={{fontSize: 82, letterSpacing: -3.6}}>A calmer Android home.</Headline>
        </div>
        <div style={{...rise(frame, fps, 22), marginTop: 20}}>
          <Body style={{fontSize: 23}}>
            In beta. Built with Flutter. Tested on a Nokia T20.
          </Body>
        </div>
        <div
          style={{
            ...rise(frame, fps, 32),
            marginTop: 34,
            display: 'inline-flex',
            alignItems: 'center',
            gap: 12,
            padding: '12px 18px',
            borderRadius: 999,
            background: PAPER,
            border: `1px solid ${LINE}`,
            fontFamily: FONT,
            fontSize: 14,
            fontWeight: 600,
            color: INK,
          }}
        >
          <span style={{width: 6, height: 6, borderRadius: '50%', background: GREEN}} />
          github.com/SimpleAppLauncher/SN-Launcher
        </div>
        <div style={{...rise(frame, fps, 40), marginTop: 46}}>
          <Beta />
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const SnLauncherVideo = () => {
  return (
    <AbsoluteFill style={{backgroundColor: BG, fontFamily: FONT, color: INK}}>
      <Backdrop />
      <Sequence from={0} durationInFrames={110}>
        <SceneFade duration={110}>
          <Intro />
        </SceneFade>
      </Sequence>
      <Sequence from={110} durationInFrames={220}>
        <SceneFade duration={220}>
          <HomeScene />
        </SceneFade>
      </Sequence>
      <Sequence from={330} durationInFrames={240}>
        <SceneFade duration={240}>
          <DockScene />
        </SceneFade>
      </Sequence>
      <Sequence from={570} durationInFrames={220}>
        <SceneFade duration={220}>
          <NowPlayingScene />
        </SceneFade>
      </Sequence>
      <Sequence from={790} durationInFrames={220}>
        <SceneFade duration={220}>
          <PerformanceScene />
        </SceneFade>
      </Sequence>
      <Sequence from={1010} durationInFrames={210}>
        <SceneFade duration={210}>
          <CompareScene />
        </SceneFade>
      </Sequence>
      <Sequence from={1220} durationInFrames={100}>
        <SceneFade duration={100}>
          <Outro />
        </SceneFade>
      </Sequence>
    </AbsoluteFill>
  );
};
