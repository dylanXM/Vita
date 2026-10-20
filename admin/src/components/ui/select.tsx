import * as React from "react";
import { Select as RS } from "radix-ui";
import { Check, ChevronDown, ChevronUp } from "lucide-react";
import { cn } from "@/lib/utils";

const Select = RS.Root;
const SelectGroup = RS.Group;
const SelectValue = RS.Value;

const SelectTrigger = React.forwardRef<
  React.ComponentRef<typeof RS.Trigger>,
  React.ComponentPropsWithoutRef<typeof RS.Trigger>
>(({ className, children, ...props }, ref) => (
  <RS.Trigger
    ref={ref}
    className={cn(
      "flex h-9 w-full items-center justify-between whitespace-nowrap rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring disabled:cursor-not-allowed disabled:opacity-50 [&>span]:line-clamp-1",
      className,
    )}
    {...props}
  >
    {children}
    <RS.Icon asChild>
      <ChevronDown className="size-4 opacity-50" />
    </RS.Icon>
  </RS.Trigger>
));
SelectTrigger.displayName = RS.Trigger.displayName;

const SelectScrollUpButton = React.forwardRef<
  React.ComponentRef<typeof RS.ScrollUpButton>,
  React.ComponentPropsWithoutRef<typeof RS.ScrollUpButton>
>(({ className, ...props }, ref) => (
  <RS.ScrollUpButton
    ref={ref}
    className={cn("flex cursor-default items-center justify-center py-1", className)}
    {...props}
  >
    <ChevronUp className="size-4" />
  </RS.ScrollUpButton>
));
SelectScrollUpButton.displayName = RS.ScrollUpButton.displayName;

const SelectScrollDownButton = React.forwardRef<
  React.ComponentRef<typeof RS.ScrollDownButton>,
  React.ComponentPropsWithoutRef<typeof RS.ScrollDownButton>
>(({ className, ...props }, ref) => (
  <RS.ScrollDownButton
    ref={ref}
    className={cn("flex cursor-default items-center justify-center py-1", className)}
    {...props}
  >
    <ChevronDown className="size-4" />
  </RS.ScrollDownButton>
));
SelectScrollDownButton.displayName = RS.ScrollDownButton.displayName;

const SelectContent = React.forwardRef<
  React.ComponentRef<typeof RS.Content>,
  React.ComponentPropsWithoutRef<typeof RS.Content>
>(({ className, children, position = "popper", ...props }, ref) => (
  <RS.Portal>
    <RS.Content
      ref={ref}
      className={cn(
        "relative z-50 min-w-[8rem] overflow-hidden rounded-md border bg-popover text-popover-foreground shadow-md",
        position === "popper" &&
          "data-[side=bottom]:translate-y-1 data-[side=left]:-translate-x-1 data-[side=right]:translate-x-1 data-[side=top]:-translate-y-1",
        className,
      )}
      position={position}
      {...props}
    >
      <SelectScrollUpButton />
      <RS.Viewport
        className={cn(
          "p-1",
          position === "popper" &&
            "h-[var(--radix-select-trigger-height)] w-full min-w-[var(--radix-select-trigger-width)]",
        )}
      >
        {children}
      </RS.Viewport>
      <SelectScrollDownButton />
    </RS.Content>
  </RS.Portal>
));
SelectContent.displayName = RS.Content.displayName;

const SelectLabel = React.forwardRef<
  React.ComponentRef<typeof RS.Label>,
  React.ComponentPropsWithoutRef<typeof RS.Label>
>(({ className, ...props }, ref) => (
  <RS.Label
    ref={ref}
    className={cn("px-2 py-1.5 text-sm font-semibold", className)}
    {...props}
  />
));
SelectLabel.displayName = RS.Label.displayName;

const SelectItem = React.forwardRef<
  React.ComponentRef<typeof RS.Item>,
  React.ComponentPropsWithoutRef<typeof RS.Item>
>(({ className, children, ...props }, ref) => (
  <RS.Item
    ref={ref}
    className={cn(
      "relative flex w-full cursor-default select-none items-center rounded-sm py-1.5 pl-2 pr-8 text-sm outline-none focus:bg-accent focus:text-accent-foreground data-[disabled]:pointer-events-none data-[disabled]:opacity-50",
      className,
    )}
    {...props}
  >
    <span className="absolute right-2 flex size-3.5 items-center justify-center">
      <RS.ItemIndicator>
        <Check className="size-4" />
      </RS.ItemIndicator>
    </span>
    <RS.ItemText>{children}</RS.ItemText>
  </RS.Item>
));
SelectItem.displayName = RS.Item.displayName;

const SelectSeparator = React.forwardRef<
  React.ComponentRef<typeof RS.Separator>,
  React.ComponentPropsWithoutRef<typeof RS.Separator>
>(({ className, ...props }, ref) => (
  <RS.Separator
    ref={ref}
    className={cn("-mx-1 my-1 h-px bg-muted", className)}
    {...props}
  />
));
SelectSeparator.displayName = RS.Separator.displayName;

export {
  Select,
  SelectGroup,
  SelectValue,
  SelectTrigger,
  SelectContent,
  SelectLabel,
  SelectItem,
  SelectSeparator,
  SelectScrollUpButton,
  SelectScrollDownButton,
};
