export function PulseWordmark({
  className,
}: {
  className?: string;
}) {
  return (
    <div className={className} aria-hidden="true">
      <svg className="pulse-wordmark-icon" viewBox="134 215 756 580">
        <path
          className="pulse-wordmark-wave"
          d="M170 512h122c24 0 36-36 56-36 23 0 35 61 57 61 20 0 39-114 88-259 9-27 27-27 36 2l98 448c7 31 27 31 39 2l72-210c6-17 18-22 36-22h80"
        />
      </svg>
      <strong>Pulse</strong>
    </div>
  );
}
