import type { ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";

export function ConfigurationButton({ label, details, icon, onClick, disabled }: {
  label: string;
  details: string[];
  icon?: ReactNode;
  onClick: () => void;
  disabled?: boolean;
}) {
  return <TooltipProvider delayDuration={150}>
    <Tooltip>
      <TooltipTrigger asChild>
        <span className="inline-flex" tabIndex={0}>
          <Button variant="outline" disabled={disabled} onClick={onClick}>{icon}{label}</Button>
        </span>
      </TooltipTrigger>
      <TooltipContent side="bottom" className="max-h-80 max-w-80 space-y-1 overflow-y-auto whitespace-pre-wrap">
        {details.map((detail, index) => <div key={`${index}-${detail}`}>{detail}</div>)}
      </TooltipContent>
    </Tooltip>
  </TooltipProvider>;
}
