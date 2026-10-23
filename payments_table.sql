-- Create payments table
CREATE TABLE IF NOT EXISTS payments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    sale_id UUID REFERENCES sales(id) ON DELETE CASCADE,
    amount DECIMAL(10,2) NOT NULL,
    payment_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    note TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS (Row Level Security)
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Create policy for distributors to see their own payments
CREATE POLICY "Distributors can view their own payments" ON payments
    FOR SELECT USING (
        sale_id IN (
            SELECT id FROM sales 
            WHERE sold_by = auth.uid()
        )
    );

-- Create policy for distributors to insert their own payments
CREATE POLICY "Distributors can insert their own payments" ON payments
    FOR INSERT WITH CHECK (
        sale_id IN (
            SELECT id FROM sales 
            WHERE sold_by = auth.uid()
        )
    );

-- Create policy for distributors to update their own payments
CREATE POLICY "Distributors can update their own payments" ON payments
    FOR UPDATE USING (
        sale_id IN (
            SELECT id FROM sales 
            WHERE sold_by = auth.uid()
        )
    );

-- Grant permissions to authenticated users
GRANT SELECT, INSERT, UPDATE ON payments TO authenticated;

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_payments_sale_id ON payments(sale_id);
CREATE INDEX IF NOT EXISTS idx_payments_payment_date ON payments(payment_date); 