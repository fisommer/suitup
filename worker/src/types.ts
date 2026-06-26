export interface CrawlRequest {
  url: string;
}

export interface CrawlResponse {
  success: boolean;
  images: string[];
  data: {
    name?: string;
    brand?: string;
    price?: { value: number; currency: string };
    colors?: string[];
    materials?: string[];
    availableSizes?: string[];
    category?: string;
    description?: string;
  };
  warnings: string[];
  error?: string;
}
