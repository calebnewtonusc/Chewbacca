import { LucideIcon } from "lucide-react";

// Standard dark card
interface CardProps {
  children: React.ReactNode;
  className?: string;
  onClick?: () => void;
}

export function Card({ children, className = "", onClick }: CardProps) {
  const isClickable = Boolean(onClick);
  return (
    <div
      onClick={onClick}
      className={`bg-zinc-900 border border-zinc-800 rounded-2xl p-6 shadow-xl
        ${isClickable ? "hover:border-zinc-700 hover:scale-[1.02] cursor-pointer" : ""}
        transition-all duration-200 ${className}`}
    >
      {children}
    </div>
  );
}

// Glassmorphism card
export function GlassCard({ children, className = "", onClick }: CardProps) {
  const isClickable = Boolean(onClick);
  return (
    <div
      onClick={onClick}
      className={`bg-white/5 backdrop-blur-md border border-white/10 rounded-2xl p-6
        ${isClickable ? "hover:border-white/20 hover:bg-white/[0.07] cursor-pointer" : ""}
        transition-all duration-200 ${className}`}
    >
      {children}
    </div>
  );
}

// Feature card, icon + title + description
interface FeatureCardProps {
  icon: LucideIcon;
  title: string;
  description: string;
  iconColor?: string;
  iconBg?: string;
}

export function FeatureCard({
  icon: Icon,
  title,
  description,
  iconColor = "text-indigo-400",
  iconBg = "bg-indigo-500/10",
}: FeatureCardProps) {
  return (
    <Card>
      <div className={`inline-flex p-2.5 ${iconBg} rounded-xl mb-4`}>
        <Icon className={`w-5 h-5 ${iconColor}`} />
      </div>
      <h3 className="text-white font-semibold text-base mb-2">{title}</h3>
      <p className="text-zinc-400 text-sm leading-relaxed">{description}</p>
    </Card>
  );
}

// Stat card
interface StatCardProps {
  value: string;
  label: string;
  change?: string;
  positive?: boolean;
}

export function StatCard({
  value,
  label,
  change,
  positive = true,
}: StatCardProps) {
  return (
    <Card>
      <p className="text-3xl font-bold text-white mb-1">{value}</p>
      <p className="text-sm text-zinc-400">{label}</p>
      {change && (
        <p
          className={`text-xs font-medium mt-2 ${positive ? "text-emerald-400" : "text-red-400"}`}
        >
          {change}
        </p>
      )}
    </Card>
  );
}

// Skeleton card
export function CardSkeleton({ lines = 3 }: { lines?: number }) {
  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 animate-pulse">
      <div className="h-10 w-10 bg-zinc-800 rounded-xl mb-4" />
      <div className="h-4 bg-zinc-800 rounded w-3/4 mb-3" />
      {Array.from({ length: lines - 1 }).map((_, i) => (
        <div
          key={i}
          className={`h-3 bg-zinc-800 rounded mb-2 ${i === lines - 2 ? "w-1/2" : "w-full"}`}
        />
      ))}
    </div>
  );
}
